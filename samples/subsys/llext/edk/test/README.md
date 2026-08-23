# Zig binding tests

The showcase sample next door demonstrates that the bindings work. This set
asserts it, and is where a test goes when an API is curated.

## Why two extensions from one source

`ext/src/main.zig` is built twice and loaded twice: once onto a kernel thread,
once onto a userspace one. The curated code is identical either way, but a
userspace extension reaches Zephyr through the `svc` marshalling in the
generated layer while a kernel one calls `z_impl_*` directly.

That difference is the point. Both binding bugs found so far -- `k_sem_take`
dispatching to the give handler, `k_thread_create` passing the stack-alloc
syscall id -- were in the marshalling, compiled cleanly, linked cleanly, and
were invisible to anything short of running the userspace path.

The probes under `../zig-import/probe/` cover the other half: that every
curated entry point compiles, links against symbols the base image exports,
and keeps the error sets it claims. Neither replaces the other.

## How a result gets back

An extension cannot return anything useful. It runs on its own thread, its
return value is discarded by the thread entry point, and in userspace it
cannot touch application memory. So the application defines one syscall,
`report(area, result)`, and the extension calls it as it finishes each area.

That is also the second thing this set tests. `report` is an
application-defined `__syscall`, so it goes through the same generator, the
same curated-binding pattern and the same module boundary as Zephyr's own
calls -- see `app/zig/`. If the application-as-binding-author path breaks,
these tests stop reporting at all.

Each area returns zero or the number of the check that failed; the application
turns that into a passing or failing ztest case, one per area per context.

## Running it

The extensions build against *this* application's EDK, not the showcase's,
because this application defines its own syscall.

```sh
west build -b frdm_mcxn947/mcxn947/cpu0 -p always -t llext-edk app
mkdir -p /tmp/test-edk && tar -xf build/zephyr/llext-edk.tar.xz -C /tmp/test-edk
export LLEXT_EDK_INSTALL_DIR=/tmp/test-edk/llext-edk

./build.sh                                        # the two extensions
west build -b frdm_mcxn947/mcxn947/cpu0 -p always app

../zig-import/gen/check_exports.sh build/zephyr/zephyr.elf \
    ext/kext/kext.llext ext/uext/uext.llext

west flash
```

The export check needs the linked application, so it comes after that build
rather than after the extension build. It answers the question `check.sh`
cannot: an extension references more than syscalls, and a compiler runtime
helper the application does not export fails at `llext_load()` on the target
with nothing to point at. `app/src/exports.c` is where those go.

Zephyr's own generated layer is shared with the showcase and is not rewritten
by this build (`REGEN_ZEPHYR=0`); only this application's own syscall layer,
under `app/zig/generated/`, belongs to it.

## The MPU partition budget

A memory domain gets as many partitions as the MPU has regions to spare, which
on this board is four. An extension with all four section types -- text,
rodata, data and bss -- uses every one of them by itself, and adding
`z_libc_partition` on top fails with `no free partition slots available`.

So the application adds the extension's own regions first, since those are what
it cannot run without, and libc afterwards only if a slot remains. These
extensions reference no libc at all -- their only undefined symbols are
`z_impl_*`, `z_arm_thread_is_in_user_mode` and the `__aeabi_*` helpers, all of
which are code in the image rather than libc data -- so losing that partition
costs them nothing. An extension that does call libc would have to give up a
section instead.

This only became reachable once the section-ordering pass let extensions have
a `.data` section at all; before that they had three regions and libc fit.

## Adding tests

Add an area to `enum test_area` in `app/include/test_api.h`, a matching member
to `Area` in `app/zig/testapi.zig`, a `testSomething()` in `ext/src/main.zig`
returning zero or a check number, a call to it in `start()`, and an
`AREA_TEST` line in `app/src/main.c`. The pair of ztest cases per context
comes out of the macro.

Areas that need a fixture -- anything reading a pin something else drives --
are deliberately absent. GPIO's testable-without-wiring part is the comptime
devicetree assertion, which lives in `../zig-import/probe/gpio.zig`.
