#!/bin/bash
#
# Build one Zig extension against the curated Zephyr API.
#
#   ./gen/build_ext.sh <main.zig> [output.o]
#
# Nothing here is pinned to a board: every flag comes out of the EDK's own
# Makefile.cflags, so pointing LLEXT_EDK_INSTALL_DIR at a different EDK is the
# only change needed to target a different board.
#
# The module graph is what enforces the layering. An extension sees `zephyr`
# (curated Zephyr), `app` (the application's own bindings) and `cimport`
# (types and constants); tier 0 is reachable only through
# `zephyr.uncurated`. `app` depends on `zephyr` and not the other way round,
# so the application's bindings can use the curated layer's public surface
# but nothing inside it -- and Zephyr's side cannot come to depend on the
# application's.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"
# shellcheck source=sdk.sh
source "$HERE/sdk.sh"

SRC="${1:?usage: build_ext.sh <main.zig> [output.o]}"
OUT="${2:-$(dirname "$SRC")/$(basename "${SRC%.zig}").o}"

[ -f "$GENERATED/syscalls.zig" ] || {
    echo "missing $GENERATED/syscalls.zig -- run gen/regen.sh first" >&2
    exit 1
}

# cimport.zig is a build product -- 15 MB of translate-c output with no review
# value -- so a fresh checkout produces it on the first build. It is also
# per-application, and applications share this directory, so it is regenerated
# whenever what is here came from a different EDK or a different API surface.
# Left alone that mismatch is silent: the wrong cimport.zig still compiles, it
# just describes the wrong application.
STAMP="$GENERATED/.edk-stamp"
WANT="$(printf '%s\n%s\n' "$LLEXT_EDK_INSTALL_DIR" "$IMPORTS_H")"
if [ ! -f "$GENERATED/cimport.zig" ]; then
    echo "==> no generated/cimport.zig yet; running gen/regen.sh"
    "$HERE/regen.sh"
elif [ ! -f "$STAMP" ] || [ "$WANT" != "$(cat "$STAMP")" ]; then
    echo "==> generated/cimport.zig is from another build; running gen/regen.sh"
    "$HERE/regen.sh"
fi

echo "==> build $(basename "$SRC") -> $OUT"
# shellcheck disable=SC2086
"$ZIG" build-obj -target "$ZIG_TARGET" $ZIG_MCPU -OReleaseSmall \
    -femit-bin="$OUT.unordered" \
    --dep zephyr --dep app --dep cimport -Mroot="$SRC" \
    --dep cimport -Mzephyr="$ZIG_IMPORT/zephyr.zig" \
    --dep zephyr --dep cimport -Mapp="$APP_API" \
    -Mcimport="$GENERATED/cimport.zig"

# Collapse each llext region to one section. LLVM interleaves .data among the
# .rodata* sections, which llext refuses to load; see $LLEXT_ORDER_LD.
LD="${LD:-$(sdk_tool ld || true)}"
[ -n "$LD" ] || { echo "no arm-zephyr-eabi-ld; set LD or ZEPHYR_SDK_INSTALL_DIR" >&2; exit 1; }
echo "==> order sections ($(basename "$LLEXT_ORDER_LD"))"
"$LD" -r -T "$LLEXT_ORDER_LD" "$OUT.unordered" -o "$OUT"
rm -f "$OUT.unordered"

"$HERE/check.sh" "$SRC" "$OUT"
