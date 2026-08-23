//! TIER 1 -- the curated Zephyr API for Zig extensions.
//!
//! This is what an extension author imports. Everything reachable from here is
//! hand-reviewed and meant to feel like Zig, not like C reached through Zig:
//! Zig error sets rather than errno, real types rather than `[*c]` pointers,
//! and constructors that make the wrong kernel object impossible to allocate.
//!
//! Curated code never marshals a syscall itself. It calls the generated tier 0
//! (`generated/syscalls.zig`), which is regenerated wholesale from the EDK.
//! That is what keeps this layer honest: if a syscall's ABI changes upstream,
//! the regenerated tier 0 no longer type-checks against the wrapper here, and
//! the build fails instead of the target misbehaving. `gen/check.sh` enforces
//! the rule.
//!
//! ## Coverage
//!
//! Curation is deliberate and incremental, so most of the syscall surface is
//! not here yet. What is missing is reachable as `zephyr.uncurated`, with C
//! signatures and errno returns -- correct, but not the API you want. Every
//! use of it is reported by `gen/check.sh` as curation work outstanding; if
//! you find yourself reaching for it, that is the signal to curate the area.

/// Curated APIs.
pub const Event = @import("api/event.zig").Event;
pub const dt = @import("api/devicetree.zig");
pub const gpio = @import("api/gpio.zig");
pub const Queue = @import("api/queue.zig").Queue;
pub const Semaphore = @import("api/sem.zig").Semaphore;
pub const Thread = @import("api/thread.zig").Thread;
pub const Timeout = @import("api/timeout.zig").Timeout;

/// Operations on the calling thread.
pub const yield = @import("api/thread.zig").yield;
pub const sleep = @import("api/thread.zig").sleep;
pub const usleep = @import("api/thread.zig").usleep;
pub const busyWait = @import("api/thread.zig").busyWait;
pub const isPreemptible = @import("api/thread.zig").isPreemptible;
pub const isUserContext = @import("api/thread.zig").isUserContext;

/// Uptime.
pub const uptime = @import("api/clock.zig").uptime;
pub const uptimeTicks = @import("api/clock.zig").uptimeTicks;

pub const UnexpectedError = @import("api/errno.zig").UnexpectedError;
/// Report a return code no wrapper models. Public so that bindings built on
/// top of this layer -- an application's own syscalls, say -- can say the
/// same thing the same way.
pub const unexpected = @import("api/errno.zig").unexpected;

/// The svc trampolines and marshalling helpers the generated layer is built
/// on. Public because an application generating its own syscall layer needs
/// somewhere to call into -- see `app/zig/generated/`.
pub const abi = @import("gen/prelude.zig");

/// Escape hatch: every Zephyr syscall the extension API can reach, exactly as
/// the C stub marshals it. ABI-correct and safe to call, but C-shaped -- reaching
/// for it means the area needs curating.
pub const uncurated = @import("generated/syscalls.zig");
