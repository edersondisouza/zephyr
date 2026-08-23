#!/usr/bin/env python3
"""Generate tier 0 -- the raw syscall layer -- from the EDK's own stub headers.

Zephyr's syscall entry points are `static inline` functions wrapping `svc`
inline assembly. `zig translate-c` cannot translate inline asm, so it drops the
body and keeps the prototype: a declaration that type-checks, links against a
symbol the base image never exports, and fails at `llext_load()` on the target.

This script replaces those declarations with real bodies. It reads the
marshalling recipe out of `include/generated/zephyr/syscalls/*.h` -- 86 headers
of rigidly uniform generated C -- and re-emits it as Zig.

The idea that makes it cheap: *no C-to-Zig type mapping happens here.*
translate-c already produced a correct Zig signature for every degraded
function; this lifts that signature verbatim out of cimport.zig and synthesises
only the body. There is no way for the generated types to drift from what the
rest of cimport.zig believes.

Output is mechanical, complete, and never hand-edited -- see gen/README.md for
how it relates to the curated layer above it.

Usage:
    LLEXT_EDK_INSTALL_DIR=... IMPORTS_DEPFILE=... \\
        gen_syscalls.py <cimport.zig> > generated/syscalls.zig
"""
import re
import sys
import glob
import os

EDK = os.environ["LLEXT_EDK_INSTALL_DIR"]
SYSCALL_DIR = f"{EDK}/include/zephyr/include/generated/zephyr/syscalls"

# --- 1. parse the generated C stubs -----------------------------------------

STUB = re.compile(
    r"^static inline (?P<ret>[^\n(]+?)\s(?P<name>\w+)\((?P<args>[^)]*)\)\n\{\n"
    r"(?P<body>.*?)\n\}\n", re.S | re.M)

# union { uintptr_t x; T val; } parm0 = { .val = sem };            plain slot
# union { struct { uintptr_t lo, hi; } split; T val; } parm1 = ..; 64-bit split
PARM = re.compile(
    r"union \{ (?:uintptr_t x; (?P<ty>.+?) val;"
    r"|struct \{ uintptr_t lo, hi; \} split; (?P<sty>.+?) val;) \} "
    r"parm(?P<idx>\d+) = \{ \.val = (?P<expr>[^}]+?) \};")

INVOKE = re.compile(
    r"arch_syscall_invoke(?P<n>\d)\((?:(?P<args>.*?), )?(?P<id>K_SYSCALL_\w+)\)", re.S)
MORE = re.compile(r"uintptr_t more\[\] = \{(?P<items>.*?)\n\t\t\};", re.S)


def parse_stubs(only=None):
    """Read every syscall stub the build can reach, keyed by function name."""
    out = {}
    for path in sorted(glob.glob(f"{SYSCALL_DIR}/*.h")):
        if only is not None and os.path.realpath(path) not in only:
            continue
        src = open(path).read()
        for m in STUB.finditer(src):
            name, body = m.group("name"), m.group("body")
            inv = INVOKE.search(body)
            if not inv:
                continue  # no trap path in this build
            parms = {}
            for p in PARM.finditer(body):
                parms[int(p.group("idx"))] = {"split": p.group("sty") is not None}
            more = MORE.search(body)
            out[name] = {
                "header": os.path.basename(path),
                "arity": int(inv.group("n")),
                "slots": [a.strip() for a in (inv.group("args") or "").split(",") if a.strip()],
                "id": inv.group("id"),
                "parms": parms,
                "more": [i.strip() for i in more.group("items").split(",")] if more else None,
            }
    return out


# --- 2. lift Zig signatures from the translate-c output ----------------------

ZSIG = re.compile(
    r"^pub extern fn (?P<name>\w+)\((?P<args>.*?)\) callconv\(\.c\) (?P<ret>.+);$", re.M)

# Every top-level name cimport.zig defines. Used to decide which identifiers in
# a lifted signature need a `c.` prefix now that the layers are separate
# modules rather than one concatenated namespace.
CDECL = re.compile(r"^pub (?:const|var|extern fn|fn|inline fn|extern var) (\w+)", re.M)


def parse_cimport(path):
    src = open(path).read()
    return ({m.group("name"): m.groupdict() for m in ZSIG.finditer(src)},
            set(CDECL.findall(src)))


def qualify(text, known):
    """Prefix cimport-owned type names with `c.`, leaving primitives alone.

    The lookbehind keeps us off field accesses and enum literals like the `.c`
    in `callconv(.c)`, which appears inside function-pointer parameter types.
    """
    return re.sub(r"(?<![.\w])([A-Za-z_]\w*)",
                  lambda m: f"c.{m.group(1)}" if m.group(1) in known else m.group(1),
                  text)


def split_args(zargs):
    """Split a Zig parameter list into (name, type) pairs, respecting nesting."""
    parts, depth, cur = [], 0, ""
    for ch in zargs:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    out = []
    for p in parts:
        p = p.strip()
        if p:
            n, _, t = p.partition(":")
            out.append((n.strip(), t.strip()))
    return out


# --- 3. emit -----------------------------------------------------------------

def slot_kind(slot):
    """Classify one argument slot of the C `arch_syscall_invokeN(...)` call."""
    m = re.fullmatch(r"parm(\d+)\.x", slot)
    if m:
        return ("plain", int(m.group(1)))
    m = re.fullmatch(r"parm(\d+)\.split\.(lo|hi)", slot)
    if m:
        return (m.group(2), int(m.group(1)))
    if slot == "(uintptr_t) &more":
        return ("more", None)
    if slot == "(uintptr_t)&ret64":
        return ("ret64", None)
    return (None, slot)


def emit(name, sc, zsig, known):
    args = split_args(zsig["args"])
    ret = qualify(zsig["ret"], known)
    sig = ", ".join(f"{n}: {qualify(t, known)}" for n, t in args)

    def to_zig(slot):
        kind, idx = slot_kind(slot)
        if kind == "plain":
            return f"p.cast({args[idx][0]})"
        if kind in ("lo", "hi"):
            return f"_{kind}{idx}"
        if kind == "more":
            return "@intFromPtr(&_more)"
        if kind == "ret64":
            return "@intFromPtr(&_ret64)"
        return None

    pre = []
    for i, parm in sc["parms"].items():
        if not parm["split"]:
            continue
        if i >= len(args):
            return None, "parm/arg mismatch"
        # A k_timeout_t or uint64_t argument occupies two consecutive slots,
        # low word first. Getting this backwards is the single most common
        # transcription bug in a hand-written wrapper.
        pre.append(f"            const _s{i}: u64 = @bitCast({args[i][0]}.ticks);")
        pre.append(f"            const _lo{i}: usize = @truncate(_s{i});")
        pre.append(f"            const _hi{i}: usize = @truncate(_s{i} >> 32);")

    if sc["more"]:
        items = [to_zig(s) for s in sc["more"]]
        if any(i is None for i in items):
            return None, "unmapped more[] slot"
        pre.append("            const _more = [_]usize{ " + ", ".join(items) + " };")

    ret64 = any(s == "(uintptr_t)&ret64" for s in sc["slots"])
    if ret64:
        pre.insert(0, "            var _ret64: u64 = undefined;")

    slots = [to_zig(s) for s in sc["slots"]]
    if any(s is None for s in slots):
        return None, "unmapped slot"

    call = (f"p.arch_syscall_invoke{sc['arity']}("
            + "".join(s + ", " for s in slots) + f"c.{sc['id']})")
    forward = ", ".join(n for n, _ in args)

    if ret64:
        trap = f"            _ = {call};\n            return @bitCast(_ret64);"
        impl = f"    return c.z_impl_{name}({forward});"
    elif ret == "void":
        trap = f"            _ = {call};\n            return;"
        impl = f"    c.z_impl_{name}({forward});"
    else:
        trap = f"            return p.from({ret}, {call});"
        impl = f"    return c.z_impl_{name}({forward});"

    lines = [
        f"/// {sc['header']} :: {sc['id']}, arity {sc['arity']}",
        f"pub fn {name}({sig}) {ret} {{",
        "    if (comptime c.CONFIG_USERSPACE == 1) {",
        "        if (p.z_syscall_trap()) {",
    ]
    if pre:
        lines += pre
    lines += [trap, "        }", "    }", "    p.compiler_barrier();", impl, "}"]
    return "\n".join(lines), None


HEADER = """\
//! TIER 0 -- RAW SYSCALLS. GENERATED FILE, DO NOT EDIT.
//!
//! Regenerate with `gen/regen.sh` whenever the EDK's syscalls change.
//! One faithful wrapper per syscall the extension API can reach: C ABI
//! signatures lifted from cimport.zig, C error codes, no ergonomics.
//!
//! Extensions should not import this directly -- use the curated `zephyr`
//! API. It is reachable as `zephyr.uncurated` for syscalls nobody has
//! curated yet, and `gen/check.sh` reports every such use as curation work
//! still to do.
//!
//! Provenance: {board}, {count} syscalls from {origin}

const c = @import("cimport");
const p = {prelude};
"""


def main():
    # Scope generation to the syscall headers imports.h actually reaches. Some
    # syscall names (atomic_add) also exist as non-syscall inlines depending on
    # Kconfig, and wrapping the wrong one produces silently wrong code.
    only = None
    deps = os.environ.get("IMPORTS_DEPFILE")
    if deps and os.path.exists(deps):
        only = {os.path.realpath(t)
                for t in re.split(r"\s+", open(deps).read().replace("\\\n", " "))
                if t.endswith(".h")}

    stubs = parse_stubs(only)
    cim, known = parse_cimport(sys.argv[1])

    # An application's own __syscall declarations land in the EDK next to
    # Zephyr's, but they are not Zephyr's and they differ from application to
    # application. Split them out by the header their stub came from, so the
    # Zephyr layer is the same file for every application and each application
    # keeps its own beside itself.
    app_headers = {h.strip() for h in os.environ.get("APP_SYSCALL_HEADERS", "").split(",") if h.strip()}
    want_app = os.environ.get("EMIT") == "app"
    if app_headers:
        stubs = {k: v for k, v in stubs.items()
                 if (v["header"] in app_headers) == want_app}

    reachable = {k: v for k, v in stubs.items() if k in cim}
    ok, fail = [], {}
    for name in sorted(reachable):
        code, err = emit(name, stubs[name], cim[name], known)
        if code:
            ok.append(code)
        else:
            fail[name] = err

    board = "unknown"
    cflags = f"{EDK}/Makefile.cflags"
    if os.path.exists(cflags):
        m = re.search(r"^LLEXT_EDK_BOARD_TARGET *= *(\S+)", open(cflags).read(), re.M)
        if m:
            board = m.group(1).strip('"')

    origin = (", ".join(sorted(app_headers)) if want_app
              else "include/generated/zephyr/syscalls/*.h")
    print(HEADER.format(board=board, count=len(ok), origin=origin,
                        prelude=os.environ.get("PRELUDE_IMPORT",
                                               '@import("../gen/prelude.zig")')))
    print("\n\n".join(ok))

    scope_out = os.environ.get("SCOPE_OUT")
    if scope_out:
        with open(scope_out, "w") as fp:
            fp.write("\n".join(sorted(stubs)) + "\n")

    sys.stderr.write(f"stubs parsed from EDK:   {len(stubs)}\n")
    sys.stderr.write(f"reachable via imports.h: {len(reachable)}\n")
    sys.stderr.write(f"emitted: {len(ok)}  failed: {len(fail)}\n")
    for n, e in fail.items():
        sys.stderr.write(f"  FAIL {n}: {e}\n")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
