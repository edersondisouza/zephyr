/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Compiler runtime helpers the extensions need.
 *
 * These are not Zephyr API and no export group covers them:
 * LLEXT_EXPORT_SYMBOL_GROUP_LIBC exports memcpy and friends by their C names,
 * not the ARM EABI aliases the compiler actually emits, and the 64-bit divide
 * helper comes from libgcc. An extension that copies a struct or divides a
 * 64-bit value needs them, and without them llext_load() fails with
 * "Could not find symbol" at run time.
 *
 * Only helpers already linked into the image can be exported. __aeabi_ldivmod
 * is deliberately absent: nothing here pulls it in, which is why the bindings
 * do their tick-to-millisecond conversion unsigned.
 */

#include <zephyr/llext/symbol.h>

extern void __aeabi_memcpy(void);
extern void __aeabi_memcpy4(void);
extern void __aeabi_memcpy8(void);
extern void __aeabi_uldivmod(void);

EXPORT_SYMBOL(__aeabi_memcpy);
EXPORT_SYMBOL(__aeabi_memcpy4);
EXPORT_SYMBOL(__aeabi_memcpy8);
EXPORT_SYMBOL(__aeabi_uldivmod);
