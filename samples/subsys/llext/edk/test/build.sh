#!/bin/bash
#
# Build the Zig binding test extensions.
#
# Prerequisite, exactly as for the showcase sample: build *this* application's
# EDK and point LLEXT_EDK_INSTALL_DIR at it. The test application defines its
# own `report` syscall, so its EDK is not the showcase's.
#
#   west build -b frdm_mcxn947/mcxn947/cpu0 -p always -t llext-edk app
#   mkdir -p /tmp/test-edk && tar -xf build/zephyr/llext-edk.tar.xz -C /tmp/test-edk
#   export LLEXT_EDK_INSTALL_DIR=/tmp/test-edk/llext-edk
#   ./build.sh
#
# Then rebuild the application; it picks the extensions up through
# app/src/main.c. After that, check what the extensions need against what it
# exports:
#
#   ../zig-import/gen/check_exports.sh build/zephyr/zephyr.elf \
#       ext/kext/kext.llext ext/uext/uext.llext

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_IMPORT="$HERE/../zig-import"

# This application's own syscall, and its bindings.
export APP_API="$HERE/app/zig/testapi.zig"
export IMPORTS_H="$HERE/app/zig/imports.h"
export APP_SYSCALL_HEADERS="test_api.h"

# Zephyr's own layer is committed and shared; only this application's part of
# the generated layer is ours to rewrite. See gen/regen.sh.
export REGEN_ZEPHYR=0

"$ZIG_IMPORT/gen/regen.sh"

# One source, two extensions. The only difference is which thread the
# application runs them on, which is the difference being tested.
"$ZIG_IMPORT/gen/build_llext.sh" "$HERE/ext/src/main.zig" "$HERE/ext/kext" kext
"$ZIG_IMPORT/gen/build_llext.sh" "$HERE/ext/src/main.zig" "$HERE/ext/uext" uext
