/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Application-private: which context a result came from. The extension does
 * not know, and must not -- it runs the same code either way.
 */

#ifndef _ZIG_LLEXT_TEST_RESULTS_H_
#define _ZIG_LLEXT_TEST_RESULTS_H_

#include <test_api.h>
#include <stdbool.h>

enum test_context {
	TEST_CONTEXT_KERNEL = 0,
	TEST_CONTEXT_USER,
	TEST_CONTEXT_COUNT
};

/** Attribute everything reported from now on to @p context. */
void test_results_collect_for(enum test_context context);

/** The result for one area, and whether it was reported at all. */
int test_result_get(enum test_context context, enum test_area area, bool *seen);

#endif /* _ZIG_LLEXT_TEST_RESULTS_H_ */
