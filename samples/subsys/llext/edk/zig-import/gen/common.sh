#!/bin/bash
# Shared setup for the zig-import scripts: derive every build flag from the
# EDK's own Makefile.cflags so that pointing LLEXT_EDK_INSTALL_DIR at a
# different board is the only change needed to target it.
#
# Sourced, not executed.

ZIG="${ZIG:-zig}"
ZIG_TARGET="${ZIG_TARGET:-thumb-freestanding-eabi}"

ZIG_IMPORT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED="$ZIG_IMPORT/generated"
IMPORTS_H="${IMPORTS_H:-$ZIG_IMPORT/../app/zig/imports.h}"

# The application's own bindings. Deliberately outside ZIG_IMPORT: they are
# not Zephyr's, they are not the Zephyr maintainer's to keep working, and
# keeping them out of the zephyr module's root directory is also what stops
# Zig seeing one file as belonging to two modules. A real project would point
# this at its own tree.
APP_API="${APP_API:-$ZIG_IMPORT/../app/zig/pubsub.zig}"

# Headers whose __syscall declarations belong to the application rather than
# to Zephyr, and where that application's generated layer is written. Split
# out so that the Zephyr layer is one shared file no matter which application
# built the EDK.
APP_SYSCALL_HEADERS="${APP_SYSCALL_HEADERS:-app_api.h}"
APP_GENERATED="${APP_GENERATED:-$(dirname "$APP_API")/generated/syscalls.zig}"

: "${LLEXT_EDK_INSTALL_DIR:?set LLEXT_EDK_INSTALL_DIR to the extracted llext-edk directory}"
CFLAGS_MK="$LLEXT_EDK_INSTALL_DIR/Makefile.cflags"
[ -f "$CFLAGS_MK" ] || { echo "no Makefile.cflags under $LLEXT_EDK_INSTALL_DIR" >&2; exit 1; }

# Makefile.cflags quotes each flag and refers to the install dir in Make
# syntax; unwrap both into something a shell can use.
edk_var() {
    grep -oE "^$1 *=.*" "$CFLAGS_MK" \
        | sed -e "s|^$1 *= *||" -e 's/"//g' \
              -e "s|\\\$(LLEXT_EDK_INSTALL_DIR)|$LLEXT_EDK_INSTALL_DIR|g"
}

# The EDK's include list ends with the GCC toolchain's own headers
# (.../lib/gcc/<triple>/<ver>/include and include-fixed). Zig ships its own
# clang headers and cannot parse GCC's arm_acle.h, so those entries have to go.
# This is why the sample's original build.sh carried a hand-trimmed copy.
INCLUDES="$(edk_var LLEXT_ALL_INCLUDE_CFLAGS | tr ' ' '\n' | grep -v '/lib/gcc/' | tr '\n' ' ')"
BASE_CFLAGS="$(edk_var LLEXT_BASE_CFLAGS)"
DEFINES="$(printf '%s\n' $BASE_CFLAGS | grep '^-D' | tr '\n' ' ')"

# Zephyr records the GCC spelling (cortex-m33); Zig wants cortex_m33.
# long_calls is what the llext relocation model needs.
GCC_MCPU="$(printf '%s\n' $BASE_CFLAGS | grep -m1 '^-mcpu=' | cut -d= -f2 || true)"
if [ -n "$GCC_MCPU" ]; then
    ZIG_MCPU="-mcpu=$(printf '%s' "$GCC_MCPU" | tr '-' '_')+long_calls"
else
    ZIG_MCPU=""
    echo "warning: no -mcpu in $CFLAGS_MK; building for the target default" >&2
fi

BOARD="$(grep -oE '^LLEXT_EDK_BOARD_TARGET *=.*' "$CFLAGS_MK" | cut -d= -f2- | tr -d ' "')"

# Section ordering for the partial link that follows the compile.
#
# gen/llext-order.ld is what every extension needs and is board-independent.
# A board that needs something else on top -- frdm_mcxn947 has to fold .bss
# into .data to fit its MPU partition budget -- puts a script named after
# itself in gen/boards/, and it is picked up automatically. Set
# LLEXT_ORDER_LD to override.
LLEXT_ORDER_LD_BOARD="$ZIG_IMPORT/gen/boards/${BOARD}.ld"
if [ -z "${LLEXT_ORDER_LD:-}" ]; then
    if [ -f "$LLEXT_ORDER_LD_BOARD" ]; then
        LLEXT_ORDER_LD="$LLEXT_ORDER_LD_BOARD"
    else
        LLEXT_ORDER_LD="$ZIG_IMPORT/gen/llext-order.ld"
    fi
fi
