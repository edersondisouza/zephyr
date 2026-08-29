//! Curated. Threads.
//!
//! The C interface spreads thread creation over three calls and ten
//! arguments: allocate a stack, allocate a thread object, then pass both plus
//! an entry point, three opaque arguments, a priority, an option word and a
//! delay to `k_thread_create`. Every one of those is a chance to pass the
//! wrong thing, and the hand-written wrapper this replaces got two of them
//! wrong.
//!
//! Here it is one call, and the entry point is an ordinary Zig function.

const std = @import("std");
const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const p = @import("../gen/prelude.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;
const word = @import("word.zig");

// ---- operations on the calling thread --------------------------------------

/// Give up the CPU to any ready thread of equal priority.
pub fn yield() void {
    syscall.k_yield();
}

/// Sleep for `timeout`. Returns the time left over in milliseconds if the
/// thread was woken early by `Thread.wakeup`, otherwise zero.
pub fn sleep(timeout: Timeout) u32 {
    return @intCast(syscall.k_sleep(timeout.raw));
}

/// Sleep for `us` microseconds. Returns the microseconds left over if woken
/// early, otherwise zero.
pub fn usleep(us: u32) u32 {
    return @intCast(syscall.k_usleep(@intCast(us)));
}

/// Spin for `us` microseconds without yielding. Prefer `sleep`.
pub fn busyWait(us: u32) void {
    syscall.k_busy_wait(us);
}

/// False when called from an ISR or a cooperative thread.
pub fn isPreemptible() bool {
    return syscall.k_is_preempt_thread() != 0;
}

/// Whether this thread is running in userspace. Zephyr's k_is_user_context is
/// an inline over the architecture check rather than a syscall, so it goes
/// through the marshalling prelude directly.
pub fn isUserContext() bool {
    return p.arch_is_user_context();
}

// ---- threads ---------------------------------------------------------------

pub const Thread = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_thread_*` call this API has not curated yet.
    raw: *c.struct_k_thread,

    /// The stack `spawn` allocated, which `destroy` has to give back. Null
    /// for a thread this extension did not create, such as `current()`.
    stack: ?*c.k_thread_stack_t = null,

    /// Zephyr's raw entry signature: three opaque arguments, C calling
    /// convention. `spawn` exists so that you rarely need it.
    pub const Entry = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void;

    /// When a newly created thread should begin running.
    ///
    /// Zephyr expresses all three of these through `k_thread_create`'s delay
    /// argument, where `K_FOREVER` means "never schedule it" rather than
    /// "wait forever" -- an overload of the timeout that is worth spelling
    /// out. Creating without starting is the useful case on a constrained
    /// target: the stack and the kernel object are acquired up front, at a
    /// point where failing is still cheap, and the thread runs later.
    pub const Start = union(enum) {
        /// As soon as the scheduler will run it.
        now,
        /// After a delay. Note that `.after = .forever` would mean "never",
        /// which is what `.manual` says properly.
        after: Timeout,
        /// Not until `start()` is called.
        manual,

        fn asDelay(self: Start) Timeout {
            return switch (self) {
                .now => .no_wait,
                .after => |timeout| timeout,
                .manual => .forever,
            };
        }

        comptime {
            // z_impl_k_thread_create schedules the new thread only when the
            // delay is not K_FOREVER, so `.manual` depends on hitting that
            // value exactly. Check it here rather than discovering on target
            // that a thread started when it should not have.
            if (asDelay(.manual).raw.ticks != c.K_TICKS_FOREVER) {
                @compileError("Start.manual must map to K_FOREVER");
            }
            if (asDelay(.now).raw.ticks != 0) {
                @compileError("Start.now must map to K_NO_WAIT");
            }
        }
    };

    pub const Options = struct {
        stack_size: usize,
        /// Negative values are cooperative priorities, which cannot be
        /// preempted; zero and above are preemptible.
        priority: i32,
        /// Thread options such as `c.K_INHERIT_PERMS` or `c.K_USER`.
        flags: u32 = 0,
        /// When the thread begins running.
        start: Start = .now,
    };

    pub const SpawnError = error{OutOfMemory};

    pub const JoinError = error{
        /// Asked not to wait, and the thread was still running.
        WouldBlock,
        /// The waiting period expired.
        TimedOut,
        /// The target is joining on the caller, or on itself.
        Deadlock,
    } || errno.UnexpectedError;

    /// Spawn a thread running `entry`, an ordinary Zig function taking up to
    /// three arguments, with `args` a tuple matching its parameters.
    ///
    ///     try Thread.spawn(poll, .{}, opts);
    ///     try Thread.spawn(worker, .{&context}, opts);
    ///
    /// The arity limit and the pointer-sized argument limit are Zephyr's:
    /// `k_thread_create` carries exactly three `void *` slots and there is
    /// nowhere to spill anything wider. Each argument is checked against the
    /// parameter it feeds, so the casting that the C interface leaves to the
    /// top of every entry point happens here instead, once, correctly.
    pub fn spawn(
        comptime entry: anytype,
        args: std.meta.ArgsTuple(@TypeOf(entry)),
        opts: Options,
    ) SpawnError!Thread {
        const params = @typeInfo(@TypeOf(entry)).@"fn".params;
        if (params.len > 3) {
            @compileError("a Zephyr thread entry point takes at most 3 arguments, " ++
                "and this one takes " ++ std.fmt.comptimePrint("{d}", .{params.len}) ++
                "; pass a pointer to a struct instead");
        }

        const trampoline = struct {
            fn call(s0: ?*anyopaque, s1: ?*anyopaque, s2: ?*anyopaque) callconv(.c) void {
                const slots = [3]?*anyopaque{ s0, s1, s2 };
                var unpacked: std.meta.ArgsTuple(@TypeOf(entry)) = undefined;
                inline for (0..params.len) |i| {
                    unpacked[i] = word.unpack(params[i].type.?, @intFromPtr(slots[i]));
                }
                @call(.auto, entry, unpacked);
            }
        };

        var slots: [3]?*anyopaque = .{ null, null, null };
        inline for (0..params.len) |i| {
            slots[i] = @ptrFromInt(word.pack(args[i]));
        }
        return spawnRaw(trampoline.call, slots, opts);
    }

    /// Spawn a thread using Zephyr's three-argument entry signature, for the
    /// cases the typed forms above cannot express.
    pub fn spawnRaw(entry: Entry, args: [3]?*anyopaque, opts: Options) SpawnError!Thread {
        // The stack allocation takes its own flag word, and the only bit it
        // reads is K_USER: with it, z_thread_stack_alloc_dyn registers the
        // stack as a kernel object, and without it the stack is plain heap.
        // A user thread given a plain-heap stack fails k_thread_create's
        // validation with "not a valid z_thread_stack_element". The two flag
        // words always have to agree on that bit, so this derives one from
        // the other rather than leaving a second field to keep in step.
        const stack_flags: c_int = if (opts.flags & c.K_USER != 0) c.K_USER else 0;
        const stack = syscall.k_thread_stack_alloc(opts.stack_size, stack_flags);
        if (stack == null) return error.OutOfMemory;
        errdefer _ = syscall.k_thread_stack_free(stack);

        const obj = syscall.k_object_alloc(c.K_OBJ_THREAD) orelse return error.OutOfMemory;
        const self: Thread = .{ .raw = @ptrCast(@alignCast(obj)), .stack = stack };

        _ = syscall.k_thread_create(
            self.raw,
            stack,
            opts.stack_size,
            entry,
            args[0],
            args[1],
            args[2],
            opts.priority,
            opts.flags,
            opts.start.asDelay().raw,
        );
        return self;
    }

    /// Begin running a thread created with `.start = .manual`.
    ///
    /// Zephyr's `k_thread_start` is a plain inline over `k_wakeup`, which is
    /// why this and `wakeup` do the same thing; they are kept apart because
    /// the intent differs, and starting a thread twice is not meaningful.
    pub fn start(self: Thread) void {
        syscall.k_wakeup(self.raw);
    }

    /// The calling thread.
    pub fn current() Thread {
        return .{ .raw = syscall.k_sched_current_thread_query() };
    }

    /// Wait for the thread to exit.
    pub fn join(self: Thread, timeout: Timeout) JoinError!void {
        return switch (syscall.k_thread_join(self.raw, timeout.raw)) {
            0 => {},
            -c.EBUSY => error.WouldBlock,
            -c.EAGAIN => error.TimedOut,
            -c.EDEADLK => error.Deadlock,
            else => |err| errno.unexpected(err),
        };
    }

    /// Terminate the thread. It does not get to run cleanup code, so prefer
    /// having the entry point return.
    pub fn abort(self: Thread) void {
        syscall.k_thread_abort(self.raw);
    }

    /// Zephyr calls this k_thread_suspend; `suspend` is a Zig keyword.
    pub fn @"suspend"(self: Thread) void {
        syscall.k_thread_suspend(self.raw);
    }

    /// Zephyr calls this k_thread_resume; `resume` is a Zig keyword.
    pub fn @"resume"(self: Thread) void {
        syscall.k_thread_resume(self.raw);
    }

    /// Wake a thread that is sleeping, so that its `sleep` returns early.
    pub fn wakeup(self: Thread) void {
        syscall.k_wakeup(self.raw);
    }

    pub fn priority(self: Thread) i32 {
        return syscall.k_thread_priority_get(self.raw);
    }

    pub fn setPriority(self: Thread, prio: i32) void {
        syscall.k_thread_priority_set(self.raw, prio);
    }

    pub const NameError = error{
        /// CONFIG_THREAD_NAME is not enabled.
        NotSupported,
        /// The name does not fit -- too long to set, or the destination
        /// buffer is too small to read it back into.
        NameTooLong,
    } || errno.UnexpectedError;

    pub fn setName(self: Thread, name: [:0]const u8) NameError!void {
        return switch (syscall.k_thread_name_set(self.raw, name.ptr)) {
            0 => {},
            -c.ENOSYS => error.NotSupported,
            -c.EINVAL => error.NameTooLong,
            else => |err| errno.unexpected(err),
        };
    }

    /// Copy the thread's name into `buf`, returning the part that was used.
    pub fn nameInto(self: Thread, buf: []u8) NameError![:0]const u8 {
        switch (syscall.k_thread_name_copy(self.raw, buf.ptr, buf.len)) {
            0 => {},
            -c.ENOSYS => return error.NotSupported,
            -c.ENOSPC => return error.NameTooLong,
            else => |err| return errno.unexpected(err),
        }
        const len = for (buf, 0..) |ch, i| {
            if (ch == 0) break i;
        } else return error.NameTooLong;
        return buf[0..len :0];
    }

    /// High-water mark: how many bytes of the thread's stack have never been
    /// used. Requires CONFIG_INIT_STACKS.
    pub fn stackUnused(self: Thread) errno.UnexpectedError!usize {
        var unused: usize = undefined;
        return switch (syscall.k_thread_stack_space_get(self.raw, &unused)) {
            0 => unused,
            else => |err| errno.unexpected(err),
        };
    }

    /// Release the stack and the kernel object that `spawn` allocated. The
    /// thread must have exited first -- `join` it, or `abort` it.
    ///
    /// Zephyr does not reclaim a dynamically allocated stack on its own, so
    /// skipping this leaks one per spawned thread.
    pub fn destroy(self: Thread) error{Busy}!void {
        if (self.stack) |stack| {
            switch (syscall.k_thread_stack_free(stack)) {
                0 => {},
                -c.EBUSY => return error.Busy,
                // -EINVAL means this was not a dynamically allocated stack,
                // which spawn guarantees it is, and -ENOSYS means dynamic
                // stacks are disabled, which the allocation would have caught.
                else => unreachable,
            }
        }
        syscall.k_object_release(self.raw);
    }
};
