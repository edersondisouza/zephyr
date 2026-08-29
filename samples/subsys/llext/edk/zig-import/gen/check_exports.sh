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
#
# Being named in the table is not the same as being callable. A syscall whose
# impl is compiled out still gets an entry, because gen_syscalls.py emits
#
#     extern __weak ALIAS_OF(no_syscall_impl) void * const z_impl_<name>;
#
# and no_syscall_impl lives in a section that is discarded, so the entry
# resolves to address 0. llext_link.c treats a zero address as not-found and
# refuses to load -- so a name-only check passes a build that then dies on the
# target with "cannot find idx N name z_impl_<name>". An export therefore
# counts here only if the symbol it points at has a nonzero address, which is
# the same test llext itself applies.
#
# A dead export is reported separately, because the fix is different: the
# symbol is already exported, and what is missing is the CONFIG that would
# compile its implementation in.

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
dead="$(mktemp)"
nmout="$(mktemp)"
trap 'rm -f "$exported" "$dead" "$nmout"' EXIT

"$NM" "$ELF" > "$nmout"

# Pass one collects the exported names, pass two looks each one up. A name
# defined more than once counts as live if any definition is real.
awk '
    FNR == NR {
        if ($NF ~ /^__llext_sym_/) { want[substr($NF, 13)] = 1 }
        next
    }
    NF == 3 && ($3 in want) {
        if ($1 ~ /^0+$/) { dead[$3] = 1 } else { live[$3] = 1 }
    }
    END {
        for (n in live) { print "live", n }
        for (n in dead) { if (!(n in live)) print "dead", n }
    }
' "$nmout" "$nmout" > "$nmout.split"

grep '^live ' "$nmout.split" | cut -d' ' -f2 | sort -u > "$exported"
grep '^dead ' "$nmout.split" | cut -d' ' -f2 | sort -u > "$dead"
rm -f "$nmout.split"

echo "==> $(wc -l < "$exported") symbols exported by $(basename "$ELF")" \
     "($(wc -l < "$dead") named but unimplemented)"

rc=0
for ext in "$@"; do
    # An undefined symbol only matters if something relocates against it.
    # Stripping .ARM.exidx leaves __aeabi_unwind_cpp_pr0 in the symbol table
    # with no relocation pointing at it, and that one is harmless.
    needed="$("$READELF" -rW "$ext" 2>/dev/null | awk '$3 ~ /^R_/ && NF >= 5 {print $NF}' | sort -u)"
    undefined="$("$NM" -u "$ext" 2>/dev/null | awk '{print $NF}' | sort -u)"
    required="$(comm -12 <(echo "$needed") <(echo "$undefined"))"
    missing="$(comm -23 <(echo "$required") "$exported")"

    # Split the two failures apart: one is missing an export, the other is
    # missing the implementation behind an export that already exists.
    unimplemented="$(comm -12 <(echo "$missing") "$dead")"
    unexported="$(comm -23 <(echo "$missing") "$dead")"

    if [ -n "$missing" ]; then
        if [ -n "$unexported" ]; then
            echo "==> ERROR: $(basename "$ext") needs symbols the application does not export:" >&2
            printf '      %s\n' $unexported >&2
            echo "    add EXPORT_SYMBOL for them, or stop calling what needs them" >&2
        fi
        if [ -n "$unimplemented" ]; then
            echo "==> ERROR: $(basename "$ext") needs symbols exported with no implementation behind them:" >&2
            printf '      %s\n' $unimplemented >&2
            echo "    these resolve to address 0, which llext rejects at load time." >&2
            echo "    enable the CONFIG that compiles them in, or stop calling what needs them" >&2
        fi
        rc=1
    else
        echo "==> check: every symbol $(basename "$ext") needs is exported"
    fi
done

exit $rc
