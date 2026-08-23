#!/bin/bash
#
#   ./gen/check_exports.sh <zephyr.elf> <extension.llext>...
#
# Does every symbol an extension actually needs exist in the application's
# export table?
#
# check.sh answers a narrower question -- it compares undefined symbols against
# the syscall list, which catches a syscall left as a bare extern. It says
# nothing about everything else an extension references, and the gap is not
# theoretical: an extension that copies a struct or divides a 64-bit value
# needs __aeabi_memcpy and __aeabi_uldivmod, no export group covers either, and
# the failure is "Could not find symbol" from llext_load() on the target.
#
# This needs the linked application, so it runs after the application build
# rather than after the extension build. Symbols are read from EXPORT_SYMBOL's
# own bookkeeping: each export leaves a __llext_sym_<name> symbol behind.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sdk.sh
source "$HERE/sdk.sh"

ELF="${1:?usage: check_exports.sh <zephyr.elf> <extension.llext>...}"
shift
[ $# -gt 0 ] || { echo "usage: check_exports.sh <zephyr.elf> <extension.llext>..." >&2; exit 1; }

NM="${NM:-$(sdk_tool nm || true)}"
READELF="${READELF:-$(sdk_tool readelf || true)}"
if [ -z "$NM" ] || [ -z "$READELF" ]; then
    echo "need arm-zephyr-eabi-nm and -readelf; set NM/READELF or ZEPHYR_SDK_INSTALL_DIR" >&2
    exit 1
fi

exported="$(mktemp)"
trap 'rm -f "$exported"' EXIT
"$NM" "$ELF" | grep -oP '__llext_sym_\K\w+' | sort -u > "$exported"
echo "==> $(wc -l < "$exported") symbols exported by $(basename "$ELF")"

rc=0
for ext in "$@"; do
    # An undefined symbol only matters if something relocates against it.
    # Stripping .ARM.exidx leaves __aeabi_unwind_cpp_pr0 in the symbol table
    # with no relocation pointing at it, and that one is harmless.
    needed="$("$READELF" -rW "$ext" 2>/dev/null | awk '$3 ~ /^R_/ && NF >= 5 {print $NF}' | sort -u)"
    undefined="$("$NM" -u "$ext" 2>/dev/null | awk '{print $NF}' | sort -u)"
    required="$(comm -12 <(echo "$needed") <(echo "$undefined"))"
    missing="$(comm -23 <(echo "$required") "$exported")"

    if [ -n "$missing" ]; then
        echo "==> ERROR: $(basename "$ext") needs symbols the application does not export:" >&2
        printf '      %s\n' $missing >&2
        echo "    add EXPORT_SYMBOL for them, or stop calling what needs them" >&2
        rc=1
    else
        echo "==> check: every symbol $(basename "$ext") needs is exported"
    fi
done

exit $rc
