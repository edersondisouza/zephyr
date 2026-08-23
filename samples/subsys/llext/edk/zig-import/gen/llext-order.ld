/*
 * Section order for llext extensions.
 *
 * llext maps each region -- text, rodata, data -- as a single span from the
 * lowest to the highest file offset of the sections in it, and refuses to load
 * when two spans overlap. Section order is therefore load-bearing, and LLVM
 * does not order them the way llext needs: it emits .data among the .rodata*
 * sections, so an extension with an initialised mutable global cannot be
 * loaded. GCC happens to group them, which is why C extensions never hit this.
 *
 * A partial link through this script collapses each region to exactly one
 * section, which makes the regions contiguous by construction rather than by
 * luck. Addresses are pinned to zero because the result is still a
 * relocatable object; without that, ld lays the sections out consecutively and
 * leaves non-zero addresses behind.
 *
 * .exported_sym, .ARM.exidx and .ARM.attributes are left as orphans. llext
 * exempts the first from the overlap rule, and the packaging step strips the
 * second.
 */
SECTIONS
{
    .text   0 : { *(.text) *(.text.*) }
    .rodata 0 : { *(.rodata) *(.rodata.*) }
    .data   0 : { *(.data) *(.data.*) }
    .bss    0 : { *(.bss) *(.bss.*) *(COMMON) }
}
