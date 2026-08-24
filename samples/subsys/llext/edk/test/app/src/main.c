/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runs the Zig binding tests. The same extension source is built twice and
 * loaded into two contexts, because that is the only difference that matters:
 * a userspace extension reaches Zephyr through the `svc` marshalling in the
 * generated layer, a kernel one calls `z_impl_*` directly, and the curated
 * code above them is identical. Every historical bug in these bindings was in
 * the marshalling, invisible to anything that only compiles and links.
 */

#include <zephyr/kernel.h>
#include <zephyr/app_memory/mem_domain.h>
#include <zephyr/llext/llext.h>
#include <zephyr/llext/buf_loader.h>
#include <zephyr/sys/libc-hooks.h>
#include <zephyr/ztest.h>

#include <test_api.h>

#include "results.h"

/*
 * The extensions are built after this application, since they need its EDK.
 * Before that has happened there is nothing to include, and this is the build
 * that produces the EDK in the first place.
 */
#if defined __has_include
#  if __has_include("../../ext/kext/kext.inc")
#    undef EDK_BUILD
#  else
#    pragma message "Test extensions not built, assuming EDK build."
#    define EDK_BUILD
#  endif
#endif

#ifndef EDK_BUILD
#include "../../ext/kext/kext.inc"
#include "../../ext/uext/uext.inc"
#endif

#define EXT_STACKSIZE 4096
#define EXT_HEAPSIZE  8192

static struct k_thread ext_thread;
static K_THREAD_STACK_DEFINE(ext_stack, EXT_STACKSIZE);
static K_HEAP_DEFINE(ext_heap, EXT_HEAPSIZE);
static struct k_mem_domain ext_domain;

static void ext_entry(void *p1, void *p2, void *p3)
{
	int (*start_fn)(void) = p1;

	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	start_fn();
}

/*
 * How each extension fared before it got as far as reporting anything. Kept
 * rather than asserted, because this runs from the suite setup, where a failed
 * assertion has no test context to unwind into -- doing that faults the board
 * and tells you nothing.
 */
static int load_status[TEST_CONTEXT_COUNT];

/*
 * Load one extension, run its `start` on a thread of the requested kind, and
 * wait for it to finish. Everything it reports on the way through is
 * attributed to that context.
 */
static int run_extension(enum test_context context, const char *name,
			 void *buf, size_t len)
{
#ifndef EDK_BUILD
	struct llext_buf_loader buf_loader = LLEXT_BUF_LOADER(buf, len);
	struct llext_load_param ldr_parm = LLEXT_LOAD_PARAM_DEFAULT;
	struct llext *ext = NULL;
	int (*start_fn)(void);
	uint32_t flags = K_INHERIT_PERMS;
	int ret;

	test_results_collect_for(context);

	ret = llext_load(&buf_loader.loader, name, &ext, &ldr_parm);
	if (ret != 0) {
		printk("[test]loading %s failed (%d)\n", name, ret);
		return ret;
	}

	start_fn = llext_find_sym(&ext->exp_tab, "start");
	if (start_fn == NULL) {
		printk("[test]%s exports no start symbol\n", name);
		llext_unload(&ext);
		return -ENOENT;
	}

	ret = k_mem_domain_init(&ext_domain, 0, NULL);
	if (ret == 0) {
		ret = llext_add_domain(ext, &ext_domain);
	}
	if (ret != 0) {
		printk("[test]%s domain setup failed (%d)\n", name, ret);
		llext_unload(&ext);
		return ret;
	}

	/*
	 * libc last, and only if there is room. A domain gets as many MPU
	 * partitions as the hardware has regions to spare -- four on this
	 * board -- and an extension with text, rodata, data and bss uses all
	 * of them by itself. Its own regions are what it cannot run without;
	 * libc it can, as long as it does not call any.
	 */
	if (k_mem_domain_add_partition(&ext_domain, &z_libc_partition) != 0) {
		printk("[test]%s: no MPU partition left for libc\n", name);
	}

	if (context == TEST_CONTEXT_USER) {
		flags |= K_USER;
	}

	k_thread_create(&ext_thread, ext_stack, EXT_STACKSIZE, ext_entry,
			start_fn, NULL, NULL, 1, flags, K_FOREVER);
	k_mem_domain_add_thread(&ext_domain, &ext_thread);
	k_thread_heap_assign(&ext_thread, &ext_heap);

	k_thread_start(&ext_thread);

	ret = k_thread_join(&ext_thread, K_SECONDS(30));
	if (ret != 0) {
		printk("[test]%s did not finish (%d)\n", name, ret);
		return ret;
	}

	llext_unload(&ext);
	return 0;
#else
	ARG_UNUSED(context);
	ARG_UNUSED(name);
	ARG_UNUSED(buf);
	ARG_UNUSED(len);
	return 0;
#endif
}

static void *run_all_extensions(void)
{
#ifndef EDK_BUILD
	load_status[TEST_CONTEXT_KERNEL] =
		run_extension(TEST_CONTEXT_KERNEL, "kext", kext_llext, kext_llext_len);
	load_status[TEST_CONTEXT_USER] =
		run_extension(TEST_CONTEXT_USER, "uext", uext_llext, uext_llext_len);
#endif
	return NULL;
}

ZTEST_SUITE(zig_bindings, NULL, run_all_extensions, NULL, NULL, NULL);

static void check(enum test_context context, enum test_area area)
{
	bool seen;
	int result = test_result_get(context, area, &seen);

	zassert_ok(load_status[context],
		   "the extension did not run; see extensions_load");
	zassert_true(seen, "extension never reported this area -- it most "
			   "likely faulted before getting there");
	zassert_equal(result, 0, "check %d failed", result);
}

/* Run this one first: everything else is meaningless if it fails. */
ZTEST(zig_bindings, test_extensions_load)
{
	zassert_ok(load_status[TEST_CONTEXT_KERNEL], "kext did not run");
	zassert_ok(load_status[TEST_CONTEXT_USER], "uext did not run");
}

/*
 * One case per area per context. The context is the whole point of the pair:
 * kernel exercises z_impl_*, user exercises the syscall marshalling.
 */
#define AREA_TEST(_name, _area)						\
	ZTEST(zig_bindings, _name##_kernel)				\
	{								\
		check(TEST_CONTEXT_KERNEL, _area);			\
	}								\
	ZTEST(zig_bindings, _name##_user)				\
	{								\
		check(TEST_CONTEXT_USER, _area);			\
	}

AREA_TEST(semaphore, TEST_SEMAPHORE)
AREA_TEST(event, TEST_EVENT)
AREA_TEST(thread, TEST_THREAD)
AREA_TEST(clock, TEST_CLOCK)
AREA_TEST(queue, TEST_QUEUE)
AREA_TEST(mutex, TEST_MUTEX)
AREA_TEST(condvar, TEST_CONDVAR)
AREA_TEST(msgq, TEST_MSGQ)
