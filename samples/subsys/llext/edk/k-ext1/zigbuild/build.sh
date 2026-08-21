#!/bin/bash
#
# Build k-ext1, the kernel-space Zig extension.
#
# The Zephyr bindings, the syscall generator and every board-specific build
# flag live in ../../zig-import -- this script only says which extension it is.
# See ../../zig-import/README.md.
#
# The output is named kext1 rather than k-ext1 because that is what the sample
# app includes: app/src/main.c pulls in ../../k-ext1/zigbuild/kext1.inc.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$HERE/../../zig-import/gen/build_llext.sh" "$HERE/../src/main.zig" "$HERE" kext1
