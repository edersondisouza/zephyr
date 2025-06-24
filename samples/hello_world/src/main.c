/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/llext/llext.h>
#include <zephyr/llext/buf_loader.h>
#include <zephyr/ztest.h>

/* Get memory from where to load ELF from devicetree */
#define SRAM_AFL DT_NODELABEL(sram_afl)
#define SRAM_AFL_SIZE DT_REG_SIZE(SRAM_AFL)

/* Buffer that holds the ELF binary, headed by its size */
struct afl_buffer {
	uint32_t size;
	uint8_t data[];
} __packed;

ZTEST(llext_afl, test_afl_loader)
{
	uintptr_t sram_afl = DT_REG_ADDR(SRAM_AFL);
	struct afl_buffer *afl_buf = (struct afl_buffer *)sram_afl;
	struct llext_buf_loader buf_loader = LLEXT_BUF_LOADER(afl_buf->data, afl_buf->size);
	struct llext_loader *loader = &buf_loader.loader;
	struct llext_load_param ldr_param = LLEXT_LOAD_PARAM_DEFAULT;
	struct llext *ext = NULL;
	int res;

	printk("SRAM AFL buffer size: %d bytes\n", afl_buf->size);
	if (afl_buf->size > SRAM_AFL_SIZE - sizeof(uint16_t)) {
		printk("Error: AFL buffer size exceeds SRAM AFL size!\n");
		return;
	}

	// Print first 64 bytes in hex format for debugging
	printk("AFL buffer data (first 64 bytes): ");
	for (int i = 0; i < 64 /*&& i < afl_buf->size*/; i++) {
		printk("%02x ", afl_buf->data[i]);
		if ((i + 1) % 16 == 0) {
			printk("\n");
		}
	}
	printk("\n");

	/* Tries to load the ELF */
	res = llext_load(loader, "afl", &ext, &ldr_param);

	if (res < 0) {
		printk("Error: Failed to load AFL extension, error code: %d\n", res);
		return;
	}

	/* If loading works, for good measure, to find a symbol */
	void (*test_entry_fn)() = llext_find_sym(&ext->exp_tab, "test_entry");
	if (!test_entry_fn) {
		printk("'test_entry' function not found in AFL extension.\n");
		llext_unload(&ext);
		return;
	}

	llext_unload(&ext);

	printk("Done!\n");

	return;
}

static void *ztest_suite_setup(void)
{
#ifdef CONFIG_LLEXT_HEAP_DYNAMIC
	/* Test runtime allocation of the LLEXT loader heap */
	zassert_ok(llext_heap_init(llext_heap_data, sizeof(llext_heap_data)));
	LOG_INF("Allocated LLEXT dynamic heap of size %uKB\n",
			(unsigned int)(sizeof(llext_heap_data)/KB(1)));
#endif
	return NULL;
}

static void ztest_suite_teardown(void *data)
{
	ARG_UNUSED(data);

#ifdef CONFIG_LLEXT_HEAP_DYNAMIC
	zassert_ok(llext_heap_uninit());
#endif
}

ZTEST_SUITE(llext_afl, NULL, ztest_suite_setup, NULL, NULL, ztest_suite_teardown);

