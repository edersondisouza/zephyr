//! Curated. Stacks.
//!
//! A `k_stack` is a last-in-first-out of `stack_data_t`, which is a machine
//! word. `Stack(T)` carries a `T` through it, so what comes out is the type
//! that went in and anything too wide is a compile error rather than a
//! truncation.
//!
//! Only the allocating constructor is here: `k_stack_init`, which takes a
//! caller-provided array, is not a syscall and is not exported, and neither is
//! `k_stack_cleanup`. As with message queues, a stack lasts as long as the
//! extension does.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const word = @import("word.zig");
const Timeout = @import("timeout.zig").Timeout;

/// A stack of `T` values.
pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The underlying kernel object. Public so that an extension can reach
        /// a `zephyr.uncurated.k_stack_*` call this API has not curated yet.
        raw: *c.struct_k_stack,

        pub const AllocError = error{
            OutOfMemory,
            /// A stack has to hold at least one entry.
            ZeroCapacity,
            /// The capacity in bytes does not fit in a size_t.
            TooLarge,
        };

        pub const PushError = error{
            /// The stack is at capacity.
            Full,
        };

        pub const PopError = error{
            /// Empty, and not willing to wait.
            WouldBlock,
            /// The waiting period expired.
            TimedOut,
        } || errno.UnexpectedError;

        /// Allocate a stack holding up to `capacity` values, taking both the
        /// object and its array from the calling thread's resource pool.
        ///
        /// Both argument checks happen here rather than in the kernel on
        /// purpose. `z_vrfy_k_stack_alloc_init` guards them with K_OOPS, so
        /// from userspace a zero capacity or an overflowing one does not
        /// return an error -- it halts the board.
        pub fn alloc(capacity: u32) AllocError!Self {
            if (capacity == 0) return error.ZeroCapacity;
            if (capacity > @as(u32, @truncate(~@as(usize, 0) / @sizeOf(c.stack_data_t)))) {
                return error.TooLarge;
            }

            const obj = syscall.k_object_alloc(c.K_OBJ_STACK) orelse return error.OutOfMemory;
            const self: Self = .{ .raw = @ptrCast(@alignCast(obj)) };
            return switch (syscall.k_stack_alloc_init(self.raw, capacity)) {
                0 => self,
                // z_impl_k_stack_alloc_init returns 0 or -ENOMEM, nothing else.
                -c.ENOMEM => error.OutOfMemory,
                else => unreachable,
            };
        }

        /// Push a value.
        pub fn push(self: Self, value: T) PushError!void {
            return switch (syscall.k_stack_push(self.raw, word.pack(value))) {
                0 => {},
                // z_impl_k_stack_push returns 0 or -ENOMEM, nothing else.
                -c.ENOMEM => error.Full,
                else => unreachable,
            };
        }

        /// Pop the most recently pushed value, waiting up to `timeout` for one.
        pub fn pop(self: Self, timeout: Timeout) PopError!T {
            var data: c.stack_data_t = undefined;
            return switch (syscall.k_stack_pop(self.raw, &data, timeout.raw)) {
                0 => word.unpack(T, data),
                -c.EBUSY => error.WouldBlock,
                -c.EAGAIN => error.TimedOut,
                else => |err| errno.unexpected(err),
            };
        }
    };
}
