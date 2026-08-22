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


mkdir -p "$GENERATED"

# Both files are built under a temporary name and moved into place only once
# they are complete, so a run interrupted partway cannot leave behind a
# cimport.zig that the next build would happily use.
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

echo "==> generate generated/syscalls.zig"
IMPORTS_DEPFILE="$GENERATED/.imports.d" SCOPE_OUT="$GENERATED/.syscalls.txt" \
    python3 "$HERE/gen_syscalls.py" "$CIMPORT" > "$SYSCALLS"

# ---- 3. publish ------------------------------------------------------------

mv -f "$CIMPORT" "$GENERATED/cimport.zig"
mv -f "$SYSCALLS" "$GENERATED/syscalls.zig"
trap - EXIT

echo "==> done"
wc -l "$GENERATED/cimport.zig" "$GENERATED/syscalls.zig"
