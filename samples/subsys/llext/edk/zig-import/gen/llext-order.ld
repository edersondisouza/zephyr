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
 * .bss is folded into .data rather than kept separate, which costs image size
 * -- the zeros are stored instead of implied -- and buys an MPU region. A
 * memory domain gets as many partitions as the MPU has regions to spare, four
 * on this board, and a userspace thread needs one of them for libc: TLS lives
 * there, and z_thread_entry reads it before the extension runs at all. That
 * leaves three for the extension, so it can have text, rodata and one of
 * data/bss. Folding them means it can have both, as long as the zeroed data
 * is small. An extension with a large .bss wants the opposite trade and
 * should keep .bss separate and stay out of .data instead.
 *
 * .exported_sym, .ARM.exidx and .ARM.attributes are left as orphans. llext
 * exempts the first from the overlap rule, and the packaging step strips the
 * second.
 */
SECTIONS
{
    .text   0 : { *(.text) *(.text.*) }
    .rodata 0 : { *(.rodata) *(.rodata.*) }
    .data   0 : { *(.data) *(.data.*) *(.bss) *(.bss.*) *(COMMON) }
}
