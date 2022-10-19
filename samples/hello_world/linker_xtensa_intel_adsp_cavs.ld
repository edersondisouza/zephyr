/*
 * Copyright 2022 The Chromium OS Authors
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/linker/sections.h>
#include <zephyr/devicetree.h>

#include <zephyr/linker/linker-defs.h>
#include <zephyr/linker/linker-tool.h>

/** enable CONFIG_SRAM2 or any other partition in soc Kconfig,
 * this is just an example to show relocation of code/data/bss script
 */
#define _SRAM2_DATA_SECTION_NAME  .sram2_data
#define _SRAM2_BSS_SECTION_NAME   .sram2_bss
#define _SRAM2_TEXT_SECTION_NAME  .sram2_text

#define SRAM2_ADDR  (DT_REG_ADDR(DT_NODELABEL(sram0)) + 32 * 1024)
#define RAM_SIZE2 (CONFIG_HP_SRAM_RESERVE - 32 * 1024)

#define SRAM3_ADDR  (DT_REG_ADDR(DT_NODELABEL(sram3)))
#define RAM_SIZE3  (DT_REG_SIZE(DT_NODELABEL(sram3)))

#define SRAM4_ADDR  ((DT_REG_ADDR(DT_NODELABEL(sram0)) - 512 * 1024 * 1024) + 16 * 1024)
#define RAM_SIZE4  (16 * 1024)

MEMORY
{
  SRAM2                  (wx) : ORIGIN = (SRAM2_ADDR), LENGTH = RAM_SIZE2
  SRAM3                  (wx) : ORIGIN = (SRAM3_ADDR), LENGTH = RAM_SIZE3
  SRAM4                  (wx) : ORIGIN = (SRAM4_ADDR), LENGTH = RAM_SIZE4
}

#define MPU_ALIGN(region_size) \
    . = ALIGN(4)

SECTIONS {
  .bss (NOLOAD) :
  {
    . = ALIGN(64);
    _bss_start = .;
    *(.dynsbss)
    *(.sbss)
    *(.sbss.*)
    *(.gnu.linkonce.sb.*)
    *(.scommon)
    *(.sbss2)
    *(.sbss2.*)
    *(.gnu.linkonce.sb2.*)
    *(.dynbss)
    *(.bss)
    *(.bss.*)
    *(.gnu.linkonce.b.*)
    *(COMMON)
  #ifdef CONFIG_CODE_DATA_RELOCATION
  #include <linker_sram_bss_relocate.ld>
  #endif
    . = ALIGN(8);
    _bss_end = .;
  } >SRAM4
}

#include <cavs-linker.ld>
