/*
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _ZIG_LLEXT_TEST_API_H_
#define _ZIG_LLEXT_TEST_API_H_

#include <zephyr/kernel.h>
#include <zephyr/toolchain.h>

#ifdef __cplusplus
extern "C" {
#endif

	/**
	 * The areas an extension reports on. One ztest case per entry, per
	 * context.
	 */
	enum test_area {
		TEST_SEMAPHORE = 0,
		TEST_EVENT,
		TEST_THREAD,
		TEST_CLOCK,
		TEST_QUEUE,
		TEST_MUTEX,
		TEST_CONDVAR,
		TEST_MSGQ,
		TEST_PIPE,
		TEST_AREA_COUNT
	};

	/**
	 * Result meaning "this area does not apply in this context".
	 *
	 * Some of what an extension can do depends on whether it runs in
	 * userspace, and an area that cannot run there has not failed. The
	 * application marks the case skipped rather than failed.
	 */
#define TEST_SKIPPED (-1)

	/**
	 * Report the outcome of one area.
	 *
	 * This exists because an extension has no other way to tell the
	 * application anything: it runs on its own thread, in userspace it
	 * cannot touch application memory, and its return value is discarded
	 * by the thread entry point. A syscall is the channel, and it is also
	 * the point -- the application defines it, so the test set exercises
	 * the application-as-binding-author path on itself.
	 *
	 * @param area which area is being reported
	 * @param result 0 if the area passed, TEST_SKIPPED if it does not
	 *               apply here, otherwise the number of the check that
	 *               failed
	 */
	__syscall void report(enum test_area area, int result);

#ifdef __cplusplus
}
#endif

#include <zephyr/syscalls/test_api.h>
#endif /* _ZIG_LLEXT_TEST_API_H_ */
