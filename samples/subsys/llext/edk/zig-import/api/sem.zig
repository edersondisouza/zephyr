//! Curated. Counting semaphores.
//!
//! Wraps the five `k_sem_*` syscalls. Marshalling is not done here -- every
//! call goes through the generated tier 0 -- so this file only decides what
//! the API should look like: types, error names, and which mistakes should be
//! impossible to express.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;

pub const Semaphore = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_sem_*` call this API has not curated yet.
    raw: *c.struct_k_sem,

    /// Both outcomes are caller mistakes, and `validate` rejects them before
    /// the kernel is asked, so this set is closed: no `Unexpected` member.
    pub const InitError = error{
        /// A semaphore with a limit of zero can never be taken.
        InvalidLimit,
        /// Initial count exceeds the limit.
        InvalidCount,
    };

    pub const AllocError = InitError || error{OutOfMemory};

    pub const TakeError = error{
        /// Asked not to wait, and the semaphore was unavailable.
        WouldBlock,
        /// The waiting period expired, or the semaphore was reset while
        /// waiting. Zephyr reports both as -EAGAIN and does not distinguish
        /// them.
        TimedOutOrReset,
    } || errno.UnexpectedError;

    /// Allocate a semaphore from the calling thread's resource pool and
    /// initialise it. This is the constructor a userspace extension wants:
    /// statically defined kernel objects are not registered for a dynamically
    /// loaded ext, so `K_SEM_DEFINE` is not an option there.
    ///
    /// The object type is implied by the method, which is the point -- asking
    /// for a semaphore cannot allocate storage sized for some other object.
    pub fn alloc(initial_count: u32, limit: u32) AllocError!Semaphore {
        try validate(initial_count, limit);
        const obj = syscall.k_object_alloc(c.K_OBJ_SEM) orelse return error.OutOfMemory;
        const self: Semaphore = .{ .raw = @ptrCast(@alignCast(obj)) };
        self.initialise(initial_count, limit);
        return self;
    }

    /// Initialise a semaphore in storage the caller already owns. Kernel
    /// extensions can use this with a plain `var sem: c.k_sem = undefined;`.
    pub fn init(storage: *c.struct_k_sem, initial_count: u32, limit: u32) InitError!Semaphore {
        try validate(initial_count, limit);
        const self: Semaphore = .{ .raw = storage };
        self.initialise(initial_count, limit);
        return self;
    }

    /// Take the semaphore, waiting up to `timeout` for it to become available.
    pub fn take(self: Semaphore, timeout: Timeout) TakeError!void {
        return switch (syscall.k_sem_take(self.raw, timeout.raw)) {
            0 => {},
            -c.EBUSY => error.WouldBlock,
            -c.EAGAIN => error.TimedOutOrReset,
            else => |err| errno.unexpected(err),
        };
    }

    /// Take the semaphore if it is available right now.
    ///
    /// `k_sem_take` under K_NO_WAIT returns only 0 or -EBUSY, so the other
    /// outcomes cannot arise from an argument this function controls. Saying
    /// so with `unreachable` keeps the error set down to the one case a caller
    /// must handle and emits nothing for the rest.
    pub fn tryTake(self: Semaphore) error{WouldBlock}!void {
        self.take(.no_wait) catch |err| return switch (err) {
            error.WouldBlock => error.WouldBlock,
            else => unreachable,
        };
    }

    /// Give the semaphore, waking one waiting thread if any.
    pub fn give(self: Semaphore) void {
        syscall.k_sem_give(self.raw);
    }

    /// Reset the count to zero. Any thread waiting on it fails its take.
    pub fn reset(self: Semaphore) void {
        syscall.k_sem_reset(self.raw);
    }

    pub fn count(self: Semaphore) u32 {
        return syscall.k_sem_count_get(self.raw);
    }

    // Zephyr returns -EINVAL for both of these. Checking before the call lets
    // the caller see which constraint they broke, and costs nothing when the
    // arguments are comptime-known.
    fn validate(initial_count: u32, limit: u32) InitError!void {
        if (limit == 0) return error.InvalidLimit;
        if (initial_count > limit) return error.InvalidCount;
    }

    /// `z_impl_k_sem_init` fails only on `CHECKIF(limit == 0U || initial_count
    /// > limit)`, which is exactly what `validate` has already rejected, so
    /// there is no failure left to report.
    fn initialise(self: Semaphore, initial_count: u32, limit: u32) void {
        switch (syscall.k_sem_init(self.raw, initial_count, limit)) {
            0 => {},
            else => unreachable,
        }
    }
};
