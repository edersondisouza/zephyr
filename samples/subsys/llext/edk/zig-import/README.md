# Zephyr bindings for Zig llext extensions

Two audiences read this directory, and they want different things from it.

**Writing an extension?** You only need `zephyr.zig`. Import it, use the API,
stop reading here:

```zig
const z = @import("zephyr");

const sem = try z.Semaphore.alloc(0, 1);
try sem.take(.ms(100));
sem.give();
```

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
misunderstandings; they were typos in repetitive work.

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
2. **Curate an area.** Take the raw wrappers plus their doxygen — 105 of the 120
   reachable syscalls carry a doc block, with `@param` semantics and `@retval`
   sets — and turn them into a Zig API. This is where taste goes.
3. **`probe/<area>.zig`** — every curated entry point called once. Its job is to
   let `check.sh` prove the whole surface links against symbols the base image
   exports.
4. **`gen/check.sh`** — tier purity, unresolved-syscall check, uncurated-usage
   report, coverage.

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

- **`c_int` is not always an errno.** Of the 51 int-returning syscalls here, 41
  document an `-Exxx` set and 33 of those return literal `0` on success. The
  rest need eyes: `k_pipe_read` and `k_pipe_write` return a byte count,
  `k_futex_wake` a thread count, and `k_sleep`, `k_usleep`,
  `k_thread_priority_get`, `k_queue_is_empty`, `k_is_preempt_thread` and the
  `k_condvar_*` family return something that is not a status at all.
- **`[*c]` carries no nullability or cardinality.** Kernel object pointers are
  reliably `*T`, but the buffer-and-length pairs (`k_pipe_read`,
  `k_thread_name_copy`, `k_stack_pop`) want a Zig slice, and pairing the
  arguments is a judgement call about parameter names.
- **Error names.** `-EAGAIN` is "timed out" for `k_mutex_lock` and "timed out or
  reset" for `k_sem_take`. Mechanical naming gets `error.Again`, which is worse
  than either.

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
  much Zig gets written. `k_timer_init` is likewise unexported, so a userspace
  ext can allocate a timer but not initialise it. Both need an app-side
  `__syscall` shim or upstream exports.
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
