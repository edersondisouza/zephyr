/*
 * Section order for llext extensions.
 *
 * llext maps each region -- text, rodata, data -- as a single span from the
 * lowest to the highest file offset of the sections in it, and refuses to load
 * when two spans overlap. Section order is therefore load-bearing, and LLVM
 * does not order them the way llext needs: it emits .data among the .rodata*
 * sections. GCC groups them, which is why no C extension has ever hit this.
 *
 * What that costs is not "extensions cannot have .data" but something worse:
 * whether an extension loads depends on where LLVM happened to put the
 * section, which moves when unrelated code is edited. A probe written to
 * reproduce the failure did not, because that time the order came out fine.
 *
 * A partial link through this script collapses each region to exactly one
 * section, so the regions are contiguous by construction rather than by luck.
 * Addresses are pinned to zero because the result is still a relocatable
 * object; without that, ld lays the sections out consecutively and leaves
 * non-zero addresses behind.
 *
 * .exported_sym, .ARM.exidx and .ARM.attributes are left as orphans. llext
 * exempts the first from the overlap rule, and the packaging step strips the
 * second.
 *
 * Nothing here is board-specific. A board that also runs short of MPU
 * partitions puts a script named after itself in boards/, which common.sh
 * selects in place of this one; boards/frdm_mcxn947_mcxn947_cpu0.ld is the
 * worked example.
 */
SECTIONS
{
    .text   0 : { *(.text) *(.text.*) }
    .rodata 0 : { *(.rodata) *(.rodata.*) }
    .data   0 : { *(.data) *(.data.*) }
    .bss    0 : { *(.bss) *(.bss.*) *(COMMON) }
}
