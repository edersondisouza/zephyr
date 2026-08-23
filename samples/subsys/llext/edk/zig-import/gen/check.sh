#!/bin/bash
#
#   ./gen/check.sh <extension-main.zig> <extension.o>
#
# Four checks. The first two are errors -- they catch the failure mode that
# motivated this whole layer, where a Zig extension builds cleanly and then
# fails at llext_load() on the target with an unresolved symbol. The last two
# are advisory, and exist to turn "an author needed something uncurated" into a
# curation backlog instead of silence.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_IMPORT="$(cd "$HERE/.." && pwd)"
GENERATED="$ZIG_IMPORT/generated"
APP_API_DIR="${APP_API_DIR:-$ZIG_IMPORT/../app/zig}"

SRC="${1:-}"
OBJ="${2:-}"
SYSCALLS="$GENERATED/.syscalls.txt"
rc=0

# ---- 1. tier purity --------------------------------------------------------
#
# Curated code must never marshal a syscall itself; it goes through the
# generated layer. This is what makes an upstream ABI change a compile error
# rather than a silent misbehaviour on target, and it is why an LLM-assisted
# curation pass cannot introduce a wrong-syscall-id bug.

# generated/ is excluded on both sides: a generated layer marshalling
# syscalls is its whole job. This is about the curated code above it.
OFFENDERS="$(grep -rln --exclude-dir=generated 'arch_syscall_invoke' \
    "$ZIG_IMPORT/api" "$APP_API_DIR" "$ZIG_IMPORT/zephyr.zig" 2>/dev/null || true)"
if [ -n "$OFFENDERS" ]; then
    echo "==> ERROR: curated code marshals syscalls directly:" >&2
    printf '      %s\n' $OFFENDERS >&2
    echo "    call generated/syscalls.zig instead; see zephyr.zig" >&2
    rc=1
else
    echo "==> check: curated layer marshals nothing itself"
fi

# ---- 2. no syscall left unresolved -----------------------------------------
#
# Zephyr exports the z_impl_* implementations, not the syscall wrappers, so an
# undefined reference to a wrapper name links against nothing the base image
# provides. translate-c produces exactly that for any function whose body it
# could not translate, which is every syscall.

# shellcheck source=sdk.sh
source "$HERE/sdk.sh"
NM="${NM:-$(sdk_tool nm || true)}"
READELF="${READELF:-$(sdk_tool readelf || true)}"

if [ -n "$OBJ" ] && [ -f "$OBJ" ] && [ -n "$NM" ] && [ -f "$SYSCALLS" ]; then
    "$NM" -u "$OBJ" | awk '{print $NF}' | sort -u > "$GENERATED/.undefined.txt"
    LEAKED="$(comm -12 "$SYSCALLS" "$GENERATED/.undefined.txt")"
    if [ -n "$LEAKED" ]; then
        echo "==> ERROR: $(basename "$OBJ") references syscalls the base image does not export:" >&2
        printf '      %s\n' $LEAKED >&2
        echo "    these would fail at llext_load(); call them through zephyr instead" >&2
        rc=1
    else
        echo "==> check: no unresolved syscall symbols in $(basename "$OBJ")"
    fi
elif [ -z "$NM" ]; then
    echo "==> skipped: arm-zephyr-eabi-nm not found (set NM= or ZEPHYR_SDK_INSTALL_DIR)" >&2
fi

# ---- 3. llext region contiguity --------------------------------------------
#
# llext maps each region -- text, rodata, data -- as one span from the lowest
# to the highest file offset of the sections belonging to it, and refuses to
# load if two spans overlap. That makes section *order* load-bearing: GCC emits
# all of .rodata* together and then .data, while LLVM interleaves them, so a
# Zig extension with an initialised mutable global can land .data in the middle
# of the rodata span and fail at llext_load() with
#
#   Region 1 ELF file range (...) overlaps with 2 (...)
#
# .exported_sym is exempt; llext_load.c makes the same exemption.

if [ -n "$OBJ" ] && [ -f "$OBJ" ] && [ -n "$READELF" ]; then
    if ! "$READELF" -SW "$OBJ" | python3 -c '
import re, sys
spans = {}
for line in sys.stdin:
    m = re.match(r"\s*\[\s*\d+\]\s+(\S+)\s+(\S+)\s+\S+\s+([0-9a-f]+)\s+([0-9a-f]+)", line)
    if not m:
        continue
    name, kind, off, size = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4), 16)
    if kind != "PROGBITS" or size == 0 or name.startswith(".exported_sym"):
        continue
    for region in ("text", "rodata", "data"):
        if name == "." + region or name.startswith("." + region + "."):
            lo, hi = spans.get(region, (off, off + size))
            spans[region] = (min(lo, off), max(hi, off + size))
            break
names = list(spans)
for i in range(len(names)):
    for j in range(i + 1, len(names)):
        a, b = spans[names[i]], spans[names[j]]
        if a[0] < b[1] and b[0] < a[1]:
            print(f"{names[i]} ({a[0]:#x}-{a[1]:#x}) overlaps {names[j]} ({b[0]:#x}-{b[1]:#x})")
            sys.exit(1)
' > "$GENERATED/.regions"; then
        echo "==> ERROR: llext regions overlap in $(basename "$OBJ"):" >&2
        sed 's/^/      /' "$GENERATED/.regions" >&2
        echo "    llext maps each region as one span and will refuse to load this." >&2
        echo "    Usually an initialised mutable global putting .data among the" >&2
        echo "    .rodata* sections; zero-initialised globals go to .bss instead." >&2
        rc=1
    else
        echo "==> check: llext regions do not overlap"
    fi
fi

# ---- 4. uncurated usage (advisory) -----------------------------------------

if [ -n "$SRC" ] && [ -f "$SRC" ]; then
    USED="$(grep -oP 'uncurated\.\K\w+' "$SRC" 2>/dev/null | sort -u || true)"
    if [ -n "$USED" ]; then
        echo "==> warning: $(basename "$SRC") reaches past the curated API:"
        printf '      %s\n' $USED
        echo "    these are correct but C-shaped; they are the next things to curate"
        [ "${STRICT:-0}" = "1" ] && rc=1
    fi
fi

# ---- 5. coverage (advisory) ------------------------------------------------

if [ -f "$SYSCALLS" ]; then
    grep -rhoP --exclude-dir=generated '(?<=\bsyscall\.)\w+' \
        "$ZIG_IMPORT/api" "$APP_API_DIR" 2>/dev/null | sort -u > "$GENERATED/.curated.txt"
    CURATED="$(comm -12 "$SYSCALLS" "$GENERATED/.curated.txt" | wc -l)"
    TOTAL="$(wc -l < "$SYSCALLS")"
    echo "==> coverage: $CURATED of $TOTAL reachable syscalls have a curated API"
fi

exit $rc
