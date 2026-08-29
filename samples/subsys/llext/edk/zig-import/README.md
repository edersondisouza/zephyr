# Zephyr bindings for Zig llext extensions

Two audiences read this directory, and they want different things from it.

**Writing an extension?** You only need `zephyr.zig`. Import it, use the API,
stop reading here:

```zig
const z = @import("zephyr");

const led = z.gpio.Pin.fromDt(z.dt.alias("led0"), "gpios");
try led.configure(.output_active);

const sem = try z.Semaphore.alloc(0, 1);
const evt = try z.Event.alloc();

_ = try z.Thread.spawn(worker, .{&context}, .{ .stack_size = 512, .priority = 2 });

if (evt.wait(TICK, .{ .timeout = .ms(100) })) |matched| {
    if (matched & TICK != 0) try led.toggle();
    try sem.take(.forever);
}
```

### What is curated

| area | reached as | notes |
|---|---|---|
| semaphores | `z.Semaphore` | `alloc` for userspace, `init` over your own storage |
| events | `z.Event` | `wait` returns `?u32`; consuming by default |
| threads | `z.Thread`, `z.sleep`, `z.yield` | `spawn` takes a Zig function and its arguments |
| mutexes | `z.Mutex` | recursive, unlike `std.Thread.Mutex` |
| condition variables | `z.Condvar` | `broadcast` returns a count, not a status |
| queues | `z.Queue(T)` | holds `*T`; append or prepend, both take from the head |
| message queues | `z.MessageQueue(T)` | copies `T` in and out; size comes from the type |
| pipes | `z.Pipe` | byte stream; `read`/`write` move *up to* what you asked. Kernel extensions only -- see *Known gaps* |
| GPIO | `z.gpio.Pin`, `z.gpio.Port` | `Flags` is a packed struct; interrupts are an enum |
| timeouts | `z.Timeout` | `.ms(100)`, `.seconds(1)`, `.forever`, `.no_wait` |
| uptime | `z.uptime`, `z.uptimeTicks` | milliseconds is unsigned; see the note in `api/clock.zig` |
| devicetree | `z.dt` | `alias`, `device`, phandle and cell access |

Everything else is callable as `zephyr.uncurated.*` — ABI-correct, C-shaped,
and reported by `gen/check.sh` as curation still to do. The application's own
API is a separate module, `app` (see below).

`gen/check.sh` prints how much of the surface that adds up to on every build,
which is why no number is written down here; it would only ever be right on the
day it was typed. What is left, by syscall count:

```sh
comm -23 generated/.syscalls.txt generated/.curated.txt
```

The larger groups at the time of writing are the rest of threads (9), timers
(8), poll (5) and stacks (3). Read *Known gaps* before starting on timers or
work queues — some of that surface is not reachable from a userspace extension
at all.

That example is `probe/readme.zig`, and it is compiled — a documented example
nobody builds rots.

**Maintaining the bindings?** The rest of this file is for you.

## Why there are three layers

`zig translate-c` cannot translate inline assembly. Zephyr's syscall entry
points are `static inline` functions wrapping `svc`, so translate-c drops the
body and keeps the prototype — 253 of them in this build. The result
type-checks, links against a symbol the base image never exports (Zephyr
exports the `z_impl_*` implementations, not the wrappers), and fails at
`llext_load()` on the target rather than at build time.

Writing the wrappers by hand is not the fix. Each one is a transcription of a
marshalling recipe — pack arguments into `uintptr_t` slots, split 64-bit values
low-word-first, pick the arity, pass the right syscall id — and the hand-written
layer this replaced had two ABI bugs in thirteen functions. They were not
misunderstandings; they were typos in repetitive work. That layer is gone: the
last of it was deleted once its final callers moved up, so nothing outside
`gen/prelude.zig` writes a syscall id by hand any more.

So the marshalling is generated and the ergonomics are curated, and the two
never mix:

| | what | who writes it | regenerated |
|---|---|---|---|
| **tier 1** | `zephyr.zig`, `api/*.zig` | maintainer, with LLM assistance | **never** |
| **probes** | `probe/*.zig` | maintainer | never |
| **tier 0** | `generated/syscalls.zig` | `gen/gen_syscalls.py` | **wholesale, every time** |
| — | `generated/cimport.zig` | `zig translate-c` | build product, not committed |

```
        extension  ──uses──▶  zephyr (tier 1, curated, Zig-native)
             │                   │ calls
             │                   ▼
             │               syscalls.zig (tier 0, generated, C-shaped)
             │                   │ svc
             │                   ▼
             │               Zephyr kernel
             │
             └──uses──▶  app  (../app/zig, the application's own bindings)
                              built on zephyr's public surface, same way
```

### The rule that holds it together

### One thing the build has to do to the object

llext maps each region -- text, rodata, data -- as a single span from the
lowest to the highest file offset of the sections in it, and refuses to load
when two spans overlap. Section order is therefore load-bearing, and LLVM does
not order them the way llext needs: it emits `.data` among the `.rodata*`
sections, so an extension with an initialised mutable global fails at
`llext_load()` with `Region 1 ELF file range (...) overlaps with 2 (...)`. GCC
groups them, which is why no C extension has ever hit this.

What that costs is not "extensions cannot have `.data`" but something worse:
whether an extension loads depends on where LLVM happened to put the section,
which moves when unrelated code is edited. A probe written to reproduce the
failure did not, because that time the order came out fine.

So `gen/build_ext.sh` runs the object through a partial link that collapses
each region to exactly one section. The regions are then contiguous by
construction rather than by luck, and `gen/check.sh` applies llext's own rule
afterwards, so a change that reintroduces the problem fails the build rather
than the load.

`gen/llext-order.ld` is what every extension needs, and is board-independent.
A board that needs something else on top puts a script named after itself in
`gen/boards/`, which is selected automatically from the EDK's own
`LLEXT_EDK_BOARD_TARGET`; boards without one get the plain ordering.
`LLEXT_ORDER_LD` overrides.

`gen/boards/frdm_mcxn947_mcxn947_cpu0.ld` is the only one so far. It folds
`.bss` into `.data`, because a memory domain on that board gets four MPU
partitions and a userspace thread always spends one on libc -- TLS lives there
and `z_thread_entry` reads it before the extension runs -- leaving three.
Folding lets an extension have text, rodata, data *and* bss within them, at the
cost of storing the zeroed data in the image rather than implying it. That is
the wrong trade for an extension with a large `.bss`, which wants the plain
ordering and to stay out of `.data` instead.

### The rule that holds it together

**Curated code never marshals a syscall itself.** `gen/check.sh` fails the build
if `arch_syscall_invoke` appears anywhere under `api/` or in the application's
bindings.

That one constraint pays for the whole design:

- **Upstream ABI changes become compile errors.** Tier 0 is regenerated from the
  EDK; if a syscall gains an argument or changes a type, the curated wrapper
  stops type-checking. No fingerprints, no staleness heuristics, no manifest to
  keep honest.
- **Curation cannot introduce ABI bugs.** A curated wrapper only chooses types
  and error names. It never touches a syscall id, so the class of bug that
  motivated this work is structurally impossible above tier 0 — which is what
  makes an LLM-assisted curation pass safe enough to be routine.
- **Coverage is derived, not tracked.** Which syscalls are curated is answered
  by grepping `api/` for `syscall.` references. Nothing to update by hand.

## The maintainer flow

```
   EDK changes                        an author needs an uncurated API
        │                                          │
        ▼                                          ▼
   gen/regen.sh                          check.sh reports it as backlog
        │                                          │
        ▼                                          ▼
   generated/*.zig  ────────────────▶  draft ──▶ LLM pass ──▶ review ──▶ api/*.zig
   (mechanical, complete)              (context: doxygen, ABI, flags)
                                                                 │
                                                                 ▼
                                                        probe/<area>.zig compiles
```

1. **`gen/regen.sh`** — deterministic. Reads the EDK's own generated syscall
   stubs and re-emits them as Zig. Signatures are lifted verbatim from
   `cimport.zig`, so no C-to-Zig type mapping happens and the types cannot drift
   from what the rest of the translated header believes.
2. **Curate an area.** Take the raw wrappers plus their doxygen — 116 of the 117
   reachable syscalls carry a doc block, with `@param` semantics and `@retval`
   sets — and turn them into a Zig API. This is where taste goes. Add a row to
   the table above while you are there; it is the one part of this file that
   goes stale on its own.
3. **`probe/<area>.zig`** — every curated entry point called once. Its job is to
   let `check.sh` prove the whole surface links against symbols the base image
   exports, and to pin down anything a type signature alone does not say:
   `probe/gpio.zig` switches on error sets exhaustively and asserts at comptime
   that `led0` still carries its devicetree polarity. Call the API from inside
   a function, not only at file scope — devicetree access reads differently in
   the two, and only the probe will notice.
4. **`gen/check.sh`** — tier purity, unresolved-syscall check, uncurated-usage
   report, coverage.
5. **`gen/check_exports.sh`** — after the application is linked, that every
   symbol the extension relocates against is in the application's export
   table. An extension references more than syscalls, and nothing else catches
   a missing compiler runtime helper before `llext_load()` does, on the target.

An application with its own `__syscall` declarations gets all of this for free:
the sample's `publish` lands in the generated stubs alongside `k_sem_take`, so
an app author curating their own API follows exactly the same steps. Those
bindings are a separate module living with the application (`app/zig/`), not
part of `zephyr` -- keeping the Zephyr maintainer's work and the application
author's apart is a property of the module graph rather than a convention.
The app module depends on `zephyr` and not the reverse, so it reaches only
the public surface any third party would have.

## Curation policy

Rules the curation step follows, so that an LLM pass and a human reach the same
answer. These are as much a part of the contract as the tier rule above.

**Do not emit code for outcomes that cannot happen.** Extensions run on
constrained devices; a branch that never executes is bytes of flash spent on
nothing. Where an outcome is genuinely impossible, say so with `unreachable` —
it costs nothing in ReleaseSmall and still panics loudly in Debug and
ReleaseSafe, so a broken assumption surfaces during development rather than
being paid for forever.

The line to draw is *why* something is impossible:

| the outcome is ruled out by… | do this | example |
|---|---|---|
| an argument this wrapper controls | `unreachable` | `tryTake` passes K_NO_WAIT, so `-EAGAIN` cannot come back |
| a precondition this wrapper checked | `unreachable`, and narrow the error set | `validate` rejects exactly what `k_sem_init`'s `CHECKIF` rejects, so `initialise` returns `void` |
| nothing — it is merely undocumented | keep `errno.UnexpectedError` | `take` gets its codes from the generic `z_pend_curr` path, which this layer does not control |

Read the implementation before claiming the first two. `kernel/sem.c` is five
lines of validation; asserting impossibility from the doxygen alone is how a
wrong `unreachable` gets written.

**Error sets are per operation, not per area.** Take each set from what that
call's `@retval` block documents. Sharing one set across an area is tempting
when the lists look similar and it is wrong in both directions at once: it
advertises failures a call cannot produce, and it has no room for the ones it
can. GPIO is the worked example -- a port access documents two errno values
and configuring an interrupt documents six, and a shared set built for
`gpio_pin_configure` silently turned `-EBUSY` and `-ENOSYS` into
`error.Unexpected`. Name them after the operation (`Pin.InterruptError`), and
let the probe switch on them exhaustively so a change has to be deliberate.

**Errors name the situation, not the errno.** `-EAGAIN` is "timed out" for
`k_mutex_lock` and "timed out or reset" for `k_sem_take`. Mechanical naming
gives `error.Again`, which is worse than either.

**The wrapped C value is always called `raw`.** Whatever a curated type wraps —
a kernel object pointer, a `k_timeout_t`, a device — the field holding it is
`raw`, and it is `pub`, so an extension can always drop to
`zephyr.uncurated` for something this layer has not covered yet. Correspondingly
the generated layer is imported as `syscall`, so a call reads
`syscall.k_sem_take(self.raw, timeout.raw)` with no ambiguity about which `raw`
is which.

## What the generator will not decide for you

Deliberately left for the curation step, because guessing produces a plausible
API that is wrong:

- **`c_int` is not always an errno.** Of the 54 int-returning syscalls here, 45
  document an `-Exxx` set and 37 of those return literal `0` on success. The
  rest need eyes: `k_pipe_read` and `k_pipe_write` return a byte count,
  `k_futex_wake` a thread count, and `k_sleep`, `k_usleep`,
  `k_thread_priority_get`, `k_queue_is_empty`, `k_is_preempt_thread` and
  `k_condvar_broadcast` return something that is not a status at all. Reading
  the implementation is the only way to be sure: `k_msgq_alloc_init` documents
  `0` and `-ENOMEM`, and also returns `-EINVAL` on an overflow the header never
  mentions.
- **`[*c]` carries no nullability or cardinality.** Kernel object pointers are
  reliably `*T`, but the buffer-and-length pairs (`k_pipe_read`,
  `k_thread_name_copy`, `k_stack_pop`) want a Zig slice, and pairing the
  arguments is a judgement call about parameter names.

## Known gaps

- **`atomic_*`** are syscall names, but in this build the in-scope definitions
  come from `atomic_builtin.h`, which translate-c also demotes. They want a
  hand-written shim over Zig's `@atomicRmw`, which is a better binding anyway.
  This is why the generator is scoped by a `zig cc -M` depfile rather than by
  name — an early version wrapped the wrong `atomic_add`.
- **`K_*_DEFINE`** macros are all broken `@compileError`s. Userspace extensions
  sidestep them anyway: statically defined kernel objects are not registered for
  a dynamically loaded ext, which is why `Semaphore.alloc` exists. They matter
  for kernel extensions and each is a small comptime function.
- **Work queues** have no syscalls *and* no `EXPORT_SYMBOL` anywhere in the
  tree, so they are unreachable from a userspace extension regardless of how
  much Zig gets written. They need an app-side `__syscall` shim or upstream
  exports.
- **Timers cannot be initialised, so none of them is usable.** Eight of the
  nine calls *are* syscalls -- `start`, `stop`, `status_get`, `status_sync`,
  `expires_ticks`, `remaining_ticks` and `user_data_get`/`set` -- and each
  guards with `K_SYSCALL_OBJ`, so they work from userspace on an initialised
  timer. `k_timer_status_sync` even blocks until expiry without a callback, so
  a polled timer would be entirely usable. But `k_timer_init` is neither a
  syscall nor exported, so there is no way to get one.

  Unlike the pipe case this is deliberate, not an oversight: a timer's expiry
  function runs in the system clock interrupt handler, so a syscall taking a
  function pointer would let a userspace thread register code to run in an ISR.
  There is nothing to fix upstream.

  Three ways out, none of them free, and all of them the application's call
  rather than this layer's: export `k_timer_init` and accept that timers are
  kernel-extension only; define an application `__syscall` that initialises
  with no callbacks, which is safe by construction and works in both contexts;
  or propose a callback-less init syscall upstream. Whichever, the export check
  turns a wrong guess into a build error naming the symbol.
- **Pipes cannot be created from userspace.** `z_vrfy_k_pipe_init` guards
  itself with `K_SYSCALL_OBJ`, which requires the object to be initialised
  already, so initialising a fresh one is rejected. Every other init verifier
  uses `K_SYSCALL_OBJ_INIT` (any state) or `K_SYSCALL_OBJ_NEVER_INIT` (must be
  fresh) -- pipe is the only one asking for the state its own call exists to
  produce. It works for a statically defined pipe, which a dynamically loaded
  userspace extension cannot have. Looks like a Zephyr bug rather than a
  design decision; `Pipe.alloc` returns `UserspaceUnsupported` rather than
  letting the oops halt the board.
- **`k_poll` cannot be reached, because its event type does not translate.**
  `struct k_poll_event` is five bitfields and an anonymous union, and
  translate-c emits `pub const struct_k_poll_event = opaque {}`. An opaque has
  no size, so an extension cannot declare storage for one, let alone read the
  `state` field back after polling. `k_poll_event_init`, the one way to fill
  one without touching the fields, is declared but not exported.

  This is a different kind of blocker from the others here: not permissions,
  not a design decision, not a missing export, but a type that does not survive
  the C-to-Zig step. The four `k_poll_signal_*` calls are unaffected --
  `struct k_poll_signal` has no bitfields and translates cleanly -- but a
  signal exists to be polled on, so they are left with the rest.

  It is fixable without upstream help, and the pieces are all present:
  `_POLL_NUM_TYPES` and `_POLL_NUM_STATES` survive, so the bit widths can be
  derived rather than guessed, and a shim header in the generation input could
  mirror the struct and `_Static_assert` its size and offsets against the real
  one, turning a layout change into a build error. That would be the first
  hand-written C in the pipeline, which is why it has not been done.
- **Callbacks** are the one structural limit. `gpio_add_callback` is not a
  syscall and dereferences `dev->api`, so interrupt-with-callback GPIO is
  kernel-extension only. A userspace extension polls, or waits on an event the
  application posts for it.

## Running it

```sh
export LLEXT_EDK_INSTALL_DIR=/path/to/extracted/llext-edk
export PATH=/path/to/zig-0.15:$PATH

cd ../ext1/zigbuild && ./build.sh    # or ../build.sh for every extension
```

That is the whole story for building an extension. `generated/cimport.zig` is a
build product, so a fresh checkout regenerates it on the first build; after
that nothing is regenerated until you ask.

The pieces underneath, if you need them directly:

```sh
./gen/regen.sh                        # after an EDK change
./gen/build_ext.sh probe/sem.zig      # object only -- what the probes use
./gen/build_llext.sh <src> <dir> <n>  # object + .llext + .inc
```

`regen.sh` is deterministic: same EDK in, byte-identical `syscalls.zig` out. So
if it rewrites the committed file, the syscalls really did change, and the
curated layer wants a look before you commit it.

`check.sh` needs `arm-zephyr-eabi-nm`, and packaging needs
`arm-zephyr-eabi-objcopy`. Both are found under `ZEPHYR_SDK_INSTALL_DIR` or
`~/zephyr-sdk-*` — note these are *not* the `arm-none-eabi-*` binaries the
sample's build scripts previously called, which is why packaging used to fail
on a machine with only the Zephyr SDK installed. Set `STRICT=1` to turn the
uncurated-usage warning into a build failure.
