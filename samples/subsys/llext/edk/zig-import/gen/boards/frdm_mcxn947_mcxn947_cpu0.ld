/*
 * Section ordering for frdm_mcxn947/mcxn947/cpu0.
 *
 * ../llext-order.ld plus .bss folded into .data. The ordering itself is the
 * same and is explained there; what this adds is a trade only some boards need
 * to make, which is why it is named after the one that needs it. Boards
 * without a file here get the plain ordering.
 *
 * A memory domain gets as many partitions as the MPU has regions to spare --
 * four on this board, after the static regions and the thread stack. A
 * userspace thread needs one of them for libc whether or not it calls any,
 * because TLS lives in that partition and z_thread_entry reads it before the
 * extension runs at all. Dropping it does not fail the load; it faults later
 * in __aeabi_read_tp.
 *
 * That leaves three for the extension, so it can have text, rodata, and one
 * of data or bss. Folding .bss into .data lets it have both: ld materialises
 * the zeros, the section disappears, and llext skips the now-empty region.
 *
 * The cost is image size, since zeroed data is stored rather than implied.
 * That is the right trade while the zeroed data is small -- four bytes in
 * these extensions -- and the wrong one for an extension with a large .bss,
 * which should use ../llext-order.ld and stay out of .data instead. Set
 * LLEXT_ORDER_LD to override the choice.
 */
SECTIONS
{
    .text   0 : { *(.text) *(.text.*) }
    .rodata 0 : { *(.rodata) *(.rodata.*) }
    .data   0 : { *(.data) *(.data.*) *(.bss) *(.bss.*) *(COMMON) }
}
