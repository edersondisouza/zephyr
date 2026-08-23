//! Curated. Queues.
//!
//! Zephyr's `k_queue` stores `void *`, so the type of what goes in is the
//! caller's problem and the type of what comes out is a cast. `Queue(T)` makes
//! it the type system's problem instead: what you append is what you get back.
//!
//! Only the allocating variants are curated, because they are the only ones an
//! extension can reach at all. `k_queue_append` and friends are not syscalls
//! and are not exported, so they are unavailable to userspace and kernel
//! extensions alike. That is a simplification rather than a limitation: the
//! non-allocating variants require the first word of every item to be reserved
//! for the kernel's use, and nothing here has to explain that.
//!
//! A queue holds pointers, not copies, so an item has to outlive its time in
//! the queue.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;

/// A queue of `*T`.
///
/// Append at the tail and take from the head for a FIFO; prepend at the head
/// and take from the head for a LIFO. Zephyr's `k_fifo` and `k_lifo` are the
/// same object with the same two orderings.
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The underlying kernel object. Public so that an extension can reach
        /// a `zephyr.uncurated.k_queue_*` call this API has not curated yet.
        raw: *c.struct_k_queue,

        pub const AppendError = error{
            /// The calling thread's resource pool could not provide a
            /// bookkeeping node.
            OutOfMemory,
        } || errno.UnexpectedError;

        /// Allocate a queue from the calling thread's resource pool and
        /// initialise it.
        pub fn alloc() error{OutOfMemory}!Self {
            const obj = syscall.k_object_alloc(c.K_OBJ_QUEUE) orelse return error.OutOfMemory;
            const self: Self = .{ .raw = @ptrCast(@alignCast(obj)) };
            syscall.k_queue_init(self.raw);
            return self;
        }

        /// Initialise a queue in storage the caller already owns.
        pub fn init(storage: *c.struct_k_queue) Self {
            const self: Self = .{ .raw = storage };
            syscall.k_queue_init(self.raw);
            return self;
        }

        /// Add an item at the tail.
        ///
        /// The kernel allocates a small bookkeeping node from the calling
        /// thread's resource pool to hold it, which is where `OutOfMemory`
        /// comes from; the item itself is not copied. The node is released
        /// when the item is taken.
        pub fn append(self: Self, item: *T) AppendError!void {
            return check(syscall.k_queue_alloc_append(self.raw, item));
        }

        /// Add an item at the head.
        pub fn prepend(self: Self, item: *T) AppendError!void {
            return check(syscall.k_queue_alloc_prepend(self.raw, item));
        }

        /// Take the item at the head, waiting up to `timeout` for one to
        /// arrive. Null means nothing arrived in time -- or that `cancelWait`
        /// was called, which Zephyr reports the same way.
        pub fn get(self: Self, timeout: Timeout) ?*T {
            const item = syscall.k_queue_get(self.raw, timeout.raw) orelse return null;
            return @ptrCast(@alignCast(item));
        }

        /// The item at the head, without taking it.
        pub fn peekHead(self: Self) ?*T {
            const item = syscall.k_queue_peek_head(self.raw) orelse return null;
            return @ptrCast(@alignCast(item));
        }

        /// The item at the tail, without taking it.
        pub fn peekTail(self: Self) ?*T {
            const item = syscall.k_queue_peek_tail(self.raw) orelse return null;
            return @ptrCast(@alignCast(item));
        }

        pub fn isEmpty(self: Self) bool {
            // k_queue_is_empty documents "non-zero if the queue is empty",
            // which is the opposite way round from most of the kernel.
            return syscall.k_queue_is_empty(self.raw) != 0;
        }

        /// Wake a thread waiting in `get`, which returns null as though it had
        /// timed out.
        pub fn cancelWait(self: Self) void {
            syscall.k_queue_cancel_wait(self.raw);
        }

        fn check(ret: i32) AppendError!void {
            return switch (ret) {
                0 => {},
                -c.ENOMEM => error.OutOfMemory,
                else => |err| errno.unexpected(err),
            };
        }
    };
}
