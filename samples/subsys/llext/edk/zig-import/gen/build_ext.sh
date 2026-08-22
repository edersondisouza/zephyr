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

SRC="${1:?usage: build_ext.sh <main.zig> [output.o]}"
OUT="${2:-$(dirname "$SRC")/$(basename "${SRC%.zig}").o}"

for f in "$GENERATED/cimport.zig" "$GENERATED/syscalls.zig"; do
    [ -f "$f" ] || { echo "missing $f -- run gen/regen.sh first" >&2; exit 1; }
done

echo "==> build $(basename "$SRC") -> $OUT"
# shellcheck disable=SC2086
"$ZIG" build-obj -target "$ZIG_TARGET" $ZIG_MCPU -OReleaseSmall \
    -femit-bin="$OUT" \
    --dep zephyr --dep app --dep cimport -Mroot="$SRC" \
    --dep cimport -Mzephyr="$ZIG_IMPORT/zephyr.zig" \
    --dep zephyr --dep cimport -Mapp="$APP_API" \
    -Mcimport="$GENERATED/cimport.zig"

"$HERE/check.sh" "$SRC" "$OUT"
