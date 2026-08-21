#!/bin/bash
#
# Regenerate the machine-owned files under generated/. Run this when the EDK
# changes -- new Zephyr version, different board, Kconfig change that adds or
# removes syscalls -- and commit the result.
#
# Nothing under api/ is touched: curated code is never regenerated. If a
# syscall's ABI changed underneath a curated wrapper, the wrapper stops
# compiling against the new tier 0, which is the whole point of forbidding
# curated code from marshalling by hand.
#
#   LLEXT_EDK_INSTALL_DIR=/path/to/llext-edk ./gen/regen.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

MANUAL_IMPORTS="$ZIG_IMPORT/manual_imports.zig"

mkdir -p "$GENERATED"

# Everything is built under a temporary name and moved into place only once it
# is complete. cimport.zig is assembled in several passes and the last of them
# appends the hand-written layer, so a run interrupted in the middle would
# otherwise leave behind a file that still compiles but is missing that layer
# -- and the next build would happily use it.
CIMPORT="$GENERATED/.cimport.zig.part"
SYSCALLS="$GENERATED/.syscalls.zig.part"
trap 'rm -f "$CIMPORT" "$SYSCALLS"' EXIT

echo "==> EDK board: ${BOARD:-unknown}   mcpu: ${GCC_MCPU:-default}"

# ---- 1. cimport.zig: translate-c over the extension API surface -------------

echo "==> translate-c -> generated/cimport.zig"
# shellcheck disable=SC2086
"$ZIG" translate-c -target "$ZIG_TARGET" $INCLUDES $DEFINES $ZIG_MCPU \
    -fno-unwind-tables "$IMPORTS_H" > "$CIMPORT"

# Devicetree node ids come through as unresolvable identifiers; turn them back
# into the strings the comptime DT_ helpers index @This() with.
sed -ri 's|(DT_N_ALIAS_\w+ = )@compileError..unable.to.translate.macro..undefined.identifier..(\w+).*$|\1"\2";|g' "$CIMPORT"
sed -ri 's|(DT_N_\w+_PH = )@compileError..unable.to.translate.macro..undefined.identifier..(\w+).*$|\1"\2";|g' "$CIMPORT"

# ---- 2. tier 0: one faithful wrapper per reachable syscall ------------------

# Scope generation to the syscall headers imports.h actually reaches, so that
# Kconfig-dependent homonyms (atomic_add) don't get a syscall wrapper.
echo "==> depfile"
# shellcheck disable=SC2086
"$ZIG" cc -target "$ZIG_TARGET" $INCLUDES $DEFINES $ZIG_MCPU \
    -M -MF "$GENERATED/.imports.d" -E "$IMPORTS_H" -o /dev/null

# Note the ordering: tier 0 lifts its signatures from the translate-c output
# *before* the legacy layer is merged in below, because merging deletes the
# `pub extern fn` declarations that the lift reads.
echo "==> generate generated/syscalls.zig"
IMPORTS_DEPFILE="$GENERATED/.imports.d" SCOPE_OUT="$GENERATED/.syscalls.txt" \
    python3 "$HERE/gen_syscalls.py" "$CIMPORT" > "$SYSCALLS"

# ---- 3. legacy layer -------------------------------------------------------
#
# manual_imports.zig predates the tiering: it is appended into cimport.zig and
# shares that namespace, so its definitions have to be cut out of the
# translate-c output first. Every function migrated up into api/ deletes one
# entry here; when the file is empty this whole step goes away, and with it the
# sed passes below.

if [ -s "$MANUAL_IMPORTS" ]; then
    echo "==> merge legacy manual_imports.zig into cimport.zig"
    for f in $(grep -Pro "(?<=pub fn )(\w+)" "$MANUAL_IMPORTS"); do
        sed -ri "s|pub extern fn $f\>.*$||g" "$CIMPORT"
        sed -ri "/pub fn $f\>.*$/,/^}/d" "$CIMPORT"
    done
    for m in $(grep -Pro "(?<=inline fn )(\w+)" "$MANUAL_IMPORTS"); do
        sed -ri "s|pub const $m\>.*$||g" "$CIMPORT"
    done
    for f in $(grep -Pro "(?<=pub inline fn )(\w+)" "$MANUAL_IMPORTS"); do
        sed -ri "/pub inline fn $f\>.*$/,/^}/d" "$CIMPORT"
    done
    for k in $(grep -Pro "(?<=^pub const )(\w+)(?= =)" "$MANUAL_IMPORTS"); do
        sed -ri "s|^pub const $k = .*$||g" "$CIMPORT"
    done
    cat "$MANUAL_IMPORTS" >> "$CIMPORT"

    # The merge is what a half-finished run silently skips, so confirm it
    # landed rather than trusting that we reached this line.
    if ! diff -q <(tail -5 "$MANUAL_IMPORTS") <(tail -5 "$CIMPORT") >/dev/null; then
        echo "ERROR: manual_imports.zig did not merge into cimport.zig" >&2
        exit 1
    fi
fi

# ---- 4. publish ------------------------------------------------------------

mv -f "$CIMPORT" "$GENERATED/cimport.zig"
mv -f "$SYSCALLS" "$GENERATED/syscalls.zig"
trap - EXIT

echo "==> done"
wc -l "$GENERATED/cimport.zig" "$GENERATED/syscalls.zig"
