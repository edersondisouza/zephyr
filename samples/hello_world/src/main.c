/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>

extern void reloc();

void main(void)
{
	printk("Hello World! %s [%p]\n", CONFIG_BOARD, main);
	reloc();
}
