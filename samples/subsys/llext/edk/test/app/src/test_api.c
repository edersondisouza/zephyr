/*
 * SPDX-License-Identifier: Apache-2.0
 */

#include <test_api.h>

#include "results.h"

#include <zephyr/kernel.h>
#include <zephyr/internal/syscall_handler.h>
#include <zephyr/llext/symbol.h>

/*
 * Results land here rather than in the extension's return value: a userspace
 * extension cannot write application memory, so the syscall boundary is the
 * only way back.
 */
static int results[TEST_CONTEXT_COUNT][TEST_AREA_COUNT];
static bool reported[TEST_CONTEXT_COUNT][TEST_AREA_COUNT];
static enum test_context current_context;

void test_results_collect_for(enum test_context context)
{
	current_context = context;
}

int test_result_get(enum test_context context, enum test_area area, bool *seen)
{
	*seen = reported[context][area];
	return results[context][area];
}

void z_impl_report(enum test_area area, int result)
{
	if (area >= TEST_AREA_COUNT) {
		return;
	}

	results[current_context][area] = result;
	reported[current_context][area] = true;
}
EXPORT_SYMBOL(z_impl_report);

#ifdef CONFIG_USERSPACE
static inline void z_vrfy_report(enum test_area area, int result)
{
	/* Both arguments are scalars, so there is nothing to copy in. */
	z_impl_report(area, result);
}
#include <zephyr/syscalls/report_mrsh.c>
#endif
