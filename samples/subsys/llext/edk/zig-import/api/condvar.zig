//! Curated. Condition variables.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Mutex = @import("mutex.zig").Mutex;
const Timeout = @import("timeout.zig").Timeout;

pub const Condvar = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_condvar_*` call this API has not curated yet.
    raw: *c.struct_k_condvar,

    pub const WaitError = error{
        /// The waiting period expired.
        TimedOut,
    } || errno.UnexpectedError;

    /// Allocate a condition variable from the calling thread's resource pool
    /// and initialise it.
    pub fn alloc() error{OutOfMemory}!Condvar {
        const obj = syscall.k_object_alloc(c.K_OBJ_CONDVAR) orelse return error.OutOfMemory;
        const self: Condvar = .{ .raw = @ptrCast(@alignCast(obj)) };
        self.initialise();
        return self;
    }

    /// Initialise a condition variable in storage the caller already owns.
    pub fn init(storage: *c.struct_k_condvar) Condvar {
        const self: Condvar = .{ .raw = storage };
        self.initialise();
        return self;
    }

    /// Release `mutex` and wait to be signalled, reacquiring it before
    /// returning. The caller must already own the mutex.
    ///
    /// Wake-ups are not proof that the condition holds -- wait in a loop that
    /// rechecks it, as with any condition variable.
    pub fn wait(self: Condvar, mutex: Mutex, timeout: Timeout) WaitError!void {
        return switch (syscall.k_condvar_wait(self.raw, mutex.raw, timeout.raw)) {
            0 => {},
            -c.EAGAIN => error.TimedOut,
            else => |err| errno.unexpected(err),
        };
    }

    /// Wake one waiting thread, if any.
    pub fn signal(self: Condvar) void {
        switch (syscall.k_condvar_signal(self.raw)) {
            0 => {},
            // z_impl_k_condvar_signal returns zero unconditionally.
            else => unreachable,
        }
    }

    /// Wake every waiting thread. Returns how many there were -- this one is
    /// a count, not a status, which is why it is not an error union.
    pub fn broadcast(self: Condvar) u32 {
        return @intCast(syscall.k_condvar_broadcast(self.raw));
    }

    /// `z_impl_k_condvar_init` returns zero unconditionally -- checked, not
    /// assumed -- so there is no failure to report.
    fn initialise(self: Condvar) void {
        switch (syscall.k_condvar_init(self.raw)) {
            0 => {},
            else => unreachable,
        }
    }
};
