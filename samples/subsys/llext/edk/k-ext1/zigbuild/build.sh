#!/bin/bash

set -ex

LLEXT_ALL_INCLUDE_CFLAGS="-I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/include/generated/zephyr -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/include/generated -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/soc/nxp/mcx -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/lib/libc/picolibc/include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/lib/libc/common/include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/lib/posix/c_lib_ext/getopt -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/lib/midi2/. -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/soc/nxp/mcx/mcxn/. -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/soc/nxp/mcx/../common -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/cmsis_6/CMSIS/Core/Include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/modules/cmsis_6/. -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/microchip/include -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/common -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/lpflexcomm -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/mcx_spc -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/port -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/cache/cache64 -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/drivers/lpflexcomm/lpuart -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/devices/MCX/MCXN/MCXN947 -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/devices/MCX/MCXN/periph -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/devices/MCX/MCXN/MCXN947 -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/devices/MCX/MCXN/MCXN947/drivers -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/nxp/mcux/mcux-sdk-ng/devices/MCX/MCXN/MCXN947/drivers -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/st/sensor/inc -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/ti/mspm0/source/ti/devices/msp/. -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/ti/mspm0/source/ti/devices/msp/m0p -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/ti/mspm0/source/ti/devices/msp/peripherals -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/ti/mspm0/source/ti/devices/msp/peripherals/m0p -I${LLEXT_EDK_INSTALL_DIR}/include/modules/hal/ti/mspm0/source/ti/devices/msp/peripherals/m0p/sysctl -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/build/modules/picolibc/picolibc/include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/build/modules/picolibc/picolibc/include -I${LLEXT_EDK_INSTALL_DIR}/include/zephyr/samples/subsys/llext/edk/app/include"

generate_import() {
    TRANSLATED_FILE=../src/cimport.zig
    MANUAL_IMPORTS=../../zig-import/manual_imports.zig
    IMPORT_H=../../zig-import/imports.h

    zig translate-c -target thumb-freestanding-eabi $LLEXT_ALL_INCLUDE_CFLAGS -fno-unwind-tables -DCPU_MCXN947VDF_cm33_core0 -mcpu=cortex_m33+long_calls $IMPORT_H > $TRANSLATED_FILE

    sed -ri 's|(DT_N_ALIAS_\w+ = )@compileError..unable.to.translate.macro..undefined.identifier..(\w+).*$|\1"\2";|g' $TRANSLATED_FILE
    sed -ri 's|(DT_N_\w+_PH = )@compileError..unable.to.translate.macro..undefined.identifier..(\w+).*$|\1"\2";|g' $TRANSLATED_FILE

    DUPLICATE_FUNCTIONS=$(grep -Pro "(?<=pub fn )(\w+)" "$MANUAL_IMPORTS")

    for function in $DUPLICATE_FUNCTIONS ; do
        sed -ri "s|pub extern fn $function\>.*$||g" $TRANSLATED_FILE
    done

    DUPLICATE_MACROS=$(grep -Pro "(?<=inline fn )(\w+)" "$MANUAL_IMPORTS")

    for macro in $DUPLICATE_MACROS ; do
        sed -ri "s|pub const $macro\>.*$||g" $TRANSLATED_FILE
    done

    DUPLICATE_INLINE_FUNCTIONS=$(grep -Pro "(?<=pub inline fn )(\w+)" "$MANUAL_IMPORTS")

    for function in $DUPLICATE_INLINE_FUNCTIONS ; do
        sed -ri "/pub inline fn $function\>.*$/,/^}/d" $TRANSLATED_FILE
    done

    cat $MANUAL_IMPORTS >> $TRANSLATED_FILE
}

generate_import

zig build-obj -I../../zig-import -target thumb-freestanding-eabi $LLEXT_ALL_INCLUDE_CFLAGS -OReleaseSmall -DCPU_MCXN947VDF_cm33_core0 -mcpu=cortex_m33+long_calls ../src/main.zig

arm-none-eabi-objcopy --remove-section .ARM.exidx main.o kext1.llext
xxd -ip kext1.llext kext1.inc
