/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>

void reloc(void)
{
	printk("Hello World from relocated! [%p]\n", reloc);
}
