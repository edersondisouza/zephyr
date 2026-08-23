//! Curated. Mutexes.
//!
//! Note that Zephyr's mutex is *recursive*: a thread that already owns one can
//! lock it again, and each lock needs its own unlock. `std.Thread.Mutex` is
//! not, so the habit of assuming a second lock deadlocks is wrong here.
//!
//! It also does priority inheritance, which is why it is not simply a binary
//! semaphore.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;

pub const Mutex = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_mutex_*` call this API has not curated yet.
    raw: *c.struct_k_mutex,

    pub const LockError = error{
        /// Asked not to wait, and someone else owns it.
        WouldBlock,
        /// The waiting period expired.
        TimedOut,
    } || errno.UnexpectedError;

    pub const UnlockError = error{
        /// Unlocking a mutex this thread does not own.
        NotOwner,
        /// Unlocking a mutex that is not locked.
        NotLocked,
    } || errno.UnexpectedError;

    /// Allocate a mutex from the calling thread's resource pool and
    /// initialise it.
    pub fn alloc() error{OutOfMemory}!Mutex {
        const obj = syscall.k_object_alloc(c.K_OBJ_MUTEX) orelse return error.OutOfMemory;
        const self: Mutex = .{ .raw = @ptrCast(@alignCast(obj)) };
        self.initialise();
        return self;
    }

    /// Initialise a mutex in storage the caller already owns.
    pub fn init(storage: *c.struct_k_mutex) Mutex {
        const self: Mutex = .{ .raw = storage };
        self.initialise();
        return self;
    }

    /// Take ownership, waiting up to `timeout`. Locking a mutex this thread
    /// already owns succeeds and raises the lock count.
    pub fn lock(self: Mutex, timeout: Timeout) LockError!void {
        return switch (syscall.k_mutex_lock(self.raw, timeout.raw)) {
            0 => {},
            -c.EBUSY => error.WouldBlock,
            -c.EAGAIN => error.TimedOut,
            else => |err| errno.unexpected(err),
        };
    }

    /// Take ownership if it is free right now.
    ///
    /// K_NO_WAIT cannot time out, so the error set narrows to the one outcome
    /// a caller has to handle.
    pub fn tryLock(self: Mutex) error{WouldBlock}!void {
        self.lock(.no_wait) catch |err| return switch (err) {
            error.WouldBlock => error.WouldBlock,
            else => unreachable,
        };
    }

    /// Give up one level of ownership. A recursively locked mutex stays locked
    /// until each lock has been matched.
    pub fn unlock(self: Mutex) UnlockError!void {
        return switch (syscall.k_mutex_unlock(self.raw)) {
            0 => {},
            -c.EPERM => error.NotOwner,
            -c.EINVAL => error.NotLocked,
            else => |err| errno.unexpected(err),
        };
    }

    /// `z_impl_k_mutex_init` returns zero unconditionally -- checked, not
    /// assumed -- so there is no failure to report.
    fn initialise(self: Mutex) void {
        switch (syscall.k_mutex_init(self.raw)) {
            0 => {},
            else => unreachable,
        }
    }
};
