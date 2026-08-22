//! Curated. The sample application's own publish/subscribe API.
//!
//! This is not part of Zephyr. `app/include/app_api.h` declares these three
//! calls as `__syscall`, so the EDK generates marshalling stubs for them
//! exactly as it does for kernel calls, they arrive in the generated layer
//! with no special casing, and curating them looks no different from curating
//! a Zephyr area. That is the whole point: an application author is a
//! maintainer of their own bindings, using the same machinery.
//!
//! In a real project this file would ship with the application rather than
//! living under `zig-import/`.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Event = @import("event.zig").Event;

/// The channels the application defines.
///
/// `CHAN_LAST` is a bound rather than a channel, so it is deliberately not
/// here. Every one of these calls returns -EINVAL for it in C; as an enum the
/// case cannot be expressed, and the error disappears from all three.
pub const Channel = enum(c.enum_Channels) {
    tick = c.CHAN_TICK,
};

pub const PublishError = error{
    /// No subscriber was ready to take the message.
    BusyChannel,
    TimedOut,
} || errno.UnexpectedError;

pub const ReceiveError = error{
    /// The destination is smaller than the channel's message.
    ReceivingBufferTooSmall,
    /// Another reader holds the channel.
    BusyChannel,
    TimedOut,
} || errno.UnexpectedError;

pub const SubscribeError = error{
    /// Unsubscribing a thread that was not subscribed.
    InvalidSubscriber,
    /// The channel has no free subscriber slot.
    TooManySubscribers,
} || errno.UnexpectedError;

/// Publish a message. `data` is a pointer to the channel's message type; its
/// length comes from the type, rather than being passed alongside it and
/// getting out of step.
pub fn publish(channel: Channel, data: anytype) PublishError!void {
    const Message = @typeInfo(@TypeOf(data)).pointer.child;
    const ret = syscall.publish(@intFromEnum(channel), @constCast(data), @sizeOf(Message));
    return switch (ret) {
        0 => {},
        -c.EBUSY => error.BusyChannel,
        -c.EAGAIN => error.TimedOut,
        else => |err| errno.unexpected(err),
    };
}

/// Read the channel's most recent message into `out`.
pub fn receive(channel: Channel, out: anytype) ReceiveError!void {
    const Message = @typeInfo(@TypeOf(out)).pointer.child;
    const ret = syscall.receive(@intFromEnum(channel), out, @sizeOf(Message));
    return switch (ret) {
        0 => {},
        // z_impl_receive returns -EINVAL for a short buffer, for a null
        // pointer and for CHAN_LAST. The latter two cannot happen here.
        -c.EINVAL => error.ReceivingBufferTooSmall,
        -c.EBUSY => error.BusyChannel,
        -c.EAGAIN => error.TimedOut,
        else => |err| errno.unexpected(err),
    };
}

/// Have `event` posted to whenever the channel is published to.
pub fn subscribe(channel: Channel, event: Event) SubscribeError!void {
    return check(syscall.register_subscriber(@intFromEnum(channel), event.raw));
}

/// Stop receiving events for the channel. In C this is the same call with a
/// null event, which is not something the signature tells you.
pub fn unsubscribe(channel: Channel) SubscribeError!void {
    return check(syscall.register_subscriber(@intFromEnum(channel), null));
}

fn check(ret: c_int) SubscribeError!void {
    return switch (ret) {
        0 => {},
        -c.ENOENT => error.InvalidSubscriber,
        -c.ENOMEM => error.TooManySubscribers,
        else => |err| errno.unexpected(err),
    };
}
