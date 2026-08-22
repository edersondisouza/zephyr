//! Curated. Event objects.
//!
//! Wraps the nine `k_event_*` syscalls. None of them can fail -- every one
//! returns a plain `uint32_t` -- so all the work here is in the shape of the
//! API rather than in error handling.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const Timeout = @import("timeout.zig").Timeout;

pub const Event = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_event_*` call this API has not curated yet, or pass
    /// the object to an application API that takes a raw `*k_event`.
    raw: *c.struct_k_event,

    /// Which of the requested events have to arrive before the wait returns.
    pub const Mode = enum { any, all };

    pub const WaitOptions = struct {
        mode: Mode = .any,

        /// Atomically clear the matched events on the way out, so that the
        /// next wait sees only what arrived after this one. This is what
        /// Zephyr's `k_event_wait_safe` exists for, and it is the default
        /// because the alternatives lose events: clearing afterwards leaves a
        /// window, and `reset` throws away everything rather than what was
        /// consumed.
        consume: bool = true,

        /// Clear every event the object is tracking *before* waiting. Racy
        /// when more than one thread waits on the same object -- prefer
        /// `consume`.
        reset: bool = false,

        timeout: Timeout = .forever,
    };

    /// Allocate an event object from the calling thread's resource pool and
    /// initialise it. The constructor implies K_OBJ_EVENT, so the object type
    /// and the Zig type cannot disagree.
    pub fn alloc() error{OutOfMemory}!Event {
        const obj = syscall.k_object_alloc(c.K_OBJ_EVENT) orelse return error.OutOfMemory;
        const self: Event = .{ .raw = @ptrCast(@alignCast(obj)) };
        syscall.k_event_init(self.raw);
        return self;
    }

    /// Initialise an event object in storage the caller already owns. Kernel
    /// extensions can use this with a plain `var evt: c.k_event = undefined;`.
    pub fn init(storage: *c.struct_k_event) Event {
        const self: Event = .{ .raw = storage };
        syscall.k_event_init(self.raw);
        return self;
    }

    /// Wait for `events`, returning the set that matched, or null if the
    /// timeout expired first.
    ///
    /// Inline so that the option struct folds away: a call with a literal
    /// `.{}` compiles down to the single syscall it selects.
    pub inline fn wait(self: Event, events: u32, opts: WaitOptions) ?u32 {
        const matched = switch (opts.mode) {
            .any => if (opts.consume)
                syscall.k_event_wait_safe(self.raw, events, opts.reset, opts.timeout.raw)
            else
                syscall.k_event_wait(self.raw, events, opts.reset, opts.timeout.raw),
            .all => if (opts.consume)
                syscall.k_event_wait_all_safe(self.raw, events, opts.reset, opts.timeout.raw)
            else
                syscall.k_event_wait_all(self.raw, events, opts.reset, opts.timeout.raw),
        };
        return if (matched == 0) null else matched;
    }

    /// Add `events` to the set being tracked. Returns the previous set.
    pub fn post(self: Event, events: u32) u32 {
        return syscall.k_event_post(self.raw, events);
    }

    /// Replace the tracked set with `events`. Returns the previous set.
    pub fn set(self: Event, events: u32) u32 {
        return syscall.k_event_set(self.raw, events);
    }

    /// Set the bits of `events` that `mask` selects, clearing the rest of the
    /// masked bits. Returns the previous value of the masked bits.
    pub fn setMasked(self: Event, events: u32, mask: u32) u32 {
        return syscall.k_event_set_masked(self.raw, events, mask);
    }

    /// Remove `events` from the set being tracked. Returns the previous set.
    pub fn clear(self: Event, events: u32) u32 {
        return syscall.k_event_clear(self.raw, events);
    }
};
