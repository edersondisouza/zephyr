# Zig binding tests

The showcase sample next door demonstrates that the bindings work. This set
asserts it, and is where a test goes when an API is curated.

## Why two extensions from one source

`ext/src/main.zig` is built twice and loaded twice: once onto a kernel thread,
once onto a userspace one. The curated code is identical either way, but a
userspace extension reaches Zephyr through the `svc` marshalling in the
generated layer while a kernel one calls `z_impl_*` directly.

That difference is the point. Every binding bug found so far was in the
marshalling, compiled cleanly, linked cleanly, and was invisible to anything
short of running the userspace path. Two predate this set: `k_sem_take`
dispatching to the give handler, and `k_thread_create` passing the stack-alloc
syscall id. Two were caught by this set, on the board, once threads were
curated:

- `arch_syscall_invoke6` passed its sixth argument in `r12`, which Zephyr's own
  trampoline lists as a clobber, so the kernel read whatever `r5` held. Six of
  the seven arities were right; only the one nothing had exercised was wrong.
  It surfaced as `Memory region 0xc (size 24) read access denied`.
- A dynamically allocated stack is only registered as a kernel object when its
  *own* flags carry `K_USER`, independently of the thread's. Passing them
  separately let the two disagree, and the board answered `not a valid
  z_thread_stack_element`. The flag is derived from the thread's now.

Neither is the kind of mistake a type system can catch, which is the argument
for keeping this set growing alongside the curated surface.

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
with nothing to point at. `app/src/exports.c` is where those go. It also
rejects an export that resolves to address 0 -- a syscall left out by the
configuration is still *named* in the table -- so that failure lands here too
rather than at load time.

Zephyr's own generated layer is shared with the showcase and is not rewritten
by this build (`REGEN_ZEPHYR=0`); only this application's own syscall layer,
under `app/zig/generated/`, belongs to it.

## The MPU partition budget

A memory domain gets as many partitions as the MPU has regions to spare, which
on this board is four. An extension with all four section types -- text,
rodata, data and bss -- uses every one of them by itself, and adding
`z_libc_partition` on top fails with `no free partition slots available`.

libc is not optional, even for an extension that calls none: TLS lives in that
partition and `z_thread_entry` reads it before the extension runs at all.
Dropping it gets an MPU fault on `__aeabi_read_tp` rather than a load failure.

So the extension gets three, and the board's own ordering script,
`../zig-import/gen/boards/frdm_mcxn947_mcxn947_cpu0.ld`, folds `.bss` into
`.data` to fit: text, rodata, data. That stores the zeroed data in the image
instead of implying it, which is the right trade only while the zeroed data is
small. An extension with a large `.bss` wants the opposite -- keep `.bss` and
stay out of `.data`, which is what the board-independent `gen/llext-order.ld`
does. The board script is selected automatically by its name; nothing here
asks for it.

The application still adds the extension's own regions first and libc after,
so if the budget is ever exceeded again the message says which one was lost
rather than failing the load outright.

## Adding tests

Add an area to `enum test_area` in `app/include/test_api.h`, a matching member
to `Area` in `app/zig/testapi.zig`, a `testSomething()` in `ext/src/main.zig`
returning zero or a check number, a call to it in `start()`, and an
`AREA_TEST` line in `app/src/main.c`. The pair of ztest cases per context
comes out of the macro.

Areas that need a fixture -- anything reading a pin something else drives --
are deliberately absent. GPIO's testable-without-wiring part is the comptime
devicetree assertion, which lives in `../zig-import/probe/gpio.zig`.
