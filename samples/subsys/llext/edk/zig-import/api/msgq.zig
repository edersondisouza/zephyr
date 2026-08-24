//! Curated. Message queues.
//!
//! A `k_msgq` copies fixed-size messages through a ring buffer, so unlike
//! `Queue`, what goes in is the message rather than a pointer to it and the
//! sender need not keep it alive. `MessageQueue(T)` takes the size from `T`
//! instead of asking for it alongside, which is one fewer thing to get out of
//! step.
//!
//! Only the allocating constructor is here, because it is the only one an
//! extension can reach: `k_msgq_init`, which takes a caller-provided ring
//! buffer, is not a syscall and is not exported. Neither is `k_msgq_cleanup`,
//! so the buffer cannot be given back either -- a queue lasts as long as the
//! extension does.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;

/// A queue of `T` values, copied in and out.
pub fn MessageQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The underlying kernel object. Public so that an extension can reach
        /// a `zephyr.uncurated.k_msgq_*` call this API has not curated yet.
        raw: *c.struct_k_msgq,

        pub const PutError = error{
            /// No room and not willing to wait for any -- or the queue was
            /// purged while this call was waiting. Zephyr reports both as
            /// -ENOMSG and does not distinguish them.
            FullOrPurged,
            /// The waiting period expired.
            TimedOut,
        } || errno.UnexpectedError;

        pub const GetError = error{
            /// Nothing to take and not willing to wait -- or the queue was
            /// purged while this call was waiting.
            EmptyOrPurged,
            /// The waiting period expired.
            TimedOut,
        } || errno.UnexpectedError;

        pub const AllocError = error{
            OutOfMemory,
            /// `@sizeOf(T)` times `max_messages` does not fit in a size_t.
            /// The header documents only 0 and -ENOMEM, but
            /// z_impl_k_msgq_alloc_init returns -EINVAL for this, so the set
            /// is closed and there is nothing left to be Unexpected about.
            TooLarge,
        };

        /// Allocate a queue holding up to `max_messages` of `T`, taking both
        /// the object and its ring buffer from the calling thread's resource
        /// pool.
        pub fn alloc(max_messages: u32) AllocError!Self {
            const obj = syscall.k_object_alloc(c.K_OBJ_MSGQ) orelse return error.OutOfMemory;
            const self: Self = .{ .raw = @ptrCast(@alignCast(obj)) };
            return switch (syscall.k_msgq_alloc_init(self.raw, @sizeOf(T), max_messages)) {
                0 => self,
                -c.ENOMEM => error.OutOfMemory,
                -c.EINVAL => error.TooLarge,
                else => unreachable,
            };
        }

        /// Copy a message to the back of the queue, waiting up to `timeout`
        /// for room.
        pub fn put(self: Self, message: T, timeout: Timeout) PutError!void {
            const copy = message;
            return switch (syscall.k_msgq_put(self.raw, &copy, timeout.raw)) {
                0 => {},
                -c.ENOMSG => error.FullOrPurged,
                -c.EAGAIN => error.TimedOut,
                else => |err| errno.unexpected(err),
            };
        }

        /// Copy a message to the *front* of the queue, so it is taken next.
        ///
        /// This one never waits, which is why it cannot time out and cannot be
        /// caught by a purge: a full queue is the only way it fails.
        pub fn putFront(self: Self, message: T) error{Full}!void {
            const copy = message;
            return switch (syscall.k_msgq_put_front(self.raw, &copy)) {
                0 => {},
                -c.ENOMSG => error.Full,
                else => unreachable,
            };
        }

        /// Take the message at the front, waiting up to `timeout` for one.
        pub fn get(self: Self, timeout: Timeout) GetError!T {
            var message: T = undefined;
            return switch (syscall.k_msgq_get(self.raw, &message, timeout.raw)) {
                0 => message,
                -c.ENOMSG => error.EmptyOrPurged,
                -c.EAGAIN => error.TimedOut,
                else => |err| errno.unexpected(err),
            };
        }

        /// The message at the front, without taking it. Null when empty.
        pub fn peek(self: Self) ?T {
            var message: T = undefined;
            return switch (syscall.k_msgq_peek(self.raw, &message)) {
                0 => message,
                // z_impl_k_msgq_peek returns 0 or -ENOMSG and nothing else.
                -c.ENOMSG => null,
                else => unreachable,
            };
        }

        /// The message `index` places from the front, without taking it. Null
        /// when the queue holds no message there.
        pub fn peekAt(self: Self, index: u32) ?T {
            var message: T = undefined;
            return switch (syscall.k_msgq_peek_at(self.raw, &message, index)) {
                0 => message,
                -c.ENOMSG => null,
                else => unreachable,
            };
        }

        /// Discard every queued message. Anything waiting to put or get is
        /// woken and told the queue was purged.
        pub fn purge(self: Self) void {
            syscall.k_msgq_purge(self.raw);
        }

        /// Messages waiting to be taken.
        pub fn used(self: Self) u32 {
            return syscall.k_msgq_num_used_get(self.raw);
        }

        /// Room for that many more.
        pub fn available(self: Self) u32 {
            return syscall.k_msgq_num_free_get(self.raw);
        }

        /// How many messages the queue was created to hold.
        pub fn capacity(self: Self) u32 {
            var attrs: c.struct_k_msgq_attrs = undefined;
            syscall.k_msgq_get_attrs(self.raw, &attrs);
            return attrs.max_msgs;
        }
    };
}
