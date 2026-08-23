#!/bin/bash
#
# Build a Zig extension and package it as a loadable llext, plus the .inc the
# sample app #includes.
#
#   ./gen/build_llext.sh <main.zig> <output-dir> <name>
#
# This is what the per-extension zigbuild/build.sh scripts call. Everything
# board-specific comes from the EDK; see gen/common.sh.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_IMPORT="$(cd "$HERE/.." && pwd)"
# shellcheck source=sdk.sh
source "$HERE/sdk.sh"

SRC="${1:?usage: build_llext.sh <main.zig> <output-dir> <name>}"
OUTDIR="${2:?usage: build_llext.sh <main.zig> <output-dir> <name>}"
NAME="${3:?usage: build_llext.sh <main.zig> <output-dir> <name>}"

mkdir -p "$OUTDIR"
"$HERE/build_ext.sh" "$SRC" "$OUTDIR/main.o"

OBJCOPY="$(sdk_tool objcopy)" || {
    echo "no arm-zephyr-eabi-objcopy found; set ZEPHYR_SDK_INSTALL_DIR" >&2
    exit 1
}

echo "==> package $NAME.llext"
"$OBJCOPY" --remove-section .ARM.exidx "$OUTDIR/main.o" "$OUTDIR/$NAME.llext"
( cd "$OUTDIR" && xxd -ip "$NAME.llext" "$NAME.inc" )

echo "==> done: $OUTDIR/$NAME.llext, $OUTDIR/$NAME.inc"
