#!/bin/bash
#
# Build ext1, the userspace Zig extension.
#
# The Zephyr bindings, the syscall generator and every board-specific build
# flag live in ../../zig-import -- this script only says which extension it is.
# See ../../zig-import/README.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$HERE/../../zig-import/gen/build_llext.sh" "$HERE/../src/main.zig" "$HERE" ext1
