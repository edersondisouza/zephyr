const std = @import("std");
const builtin = @import("builtin");

inline fn Z_TIMEOUT_TICKS_INIT(comptime ticks: c_int) k_timeout_t {
    return k_timeout_t{ .ticks = ticks };
}

pub fn arch_syscall_invoke1(arg1: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (_SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
        : .{ .r8 = true, .memory = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true }
    );
}

pub fn arch_syscall_invoke2(arg1: usize, arg2: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (_SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
        : .{ .r8 = true, .memory = true, .r2 = true, .r3 = true, .r12 = true }
    );
}

pub fn arch_syscall_invoke3(arg1: usize, arg2: usize, arg3: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (_SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
        : .{ .r8 = true, .memory = true, .r3 = true, .r12 = true }
    );
}

pub fn arch_syscall_invoke5(arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (_SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
        : .{ .r8 = true, .memory = true, .r12 = true }
    );
}

pub fn arch_syscall_invoke6(arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (_SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
          [arg6] "{r12}" (arg6),
        : .{ .r8 = true, .memory = true }
    );
}

pub fn arch_is_user_context() bool {
    if (comptime CONFIG_CPU_CORTEX_M == 1) {
        var value: u32 = undefined;

        asm volatile ("mrs %[value], IPSR\n"
            : [value] "=r" (value) : : .{});

        if (value != 0) {
            return false;
        }
    }

    return z_arm_thread_is_in_user_mode();
}

inline fn compiler_barrier() void {
    asm volatile ("" : : : .{.memory = true});
}

pub fn k_object_alloc(otype: enum_k_objects, comptime T: type) !*T{
    var ret: usize = undefined;

    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            ret = arch_syscall_invoke1(otype, K_SYSCALL_K_OBJECT_ALLOC);
            return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
        }
    }

    compiler_barrier();
    ret = @intFromPtr(z_impl_k_object_alloc(otype));

    return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
}

// k_event_* migrated to the curated layer: see zig-import/api/event.zig

pub const SUCCESS = 0;

pub const UnexpectedError = error{
    Unexpected,
};

pub fn unexpectedErrno(err: i32) UnexpectedError {
    if (builtin.mode == .Debug) {
        printk("unexpected errno: %d\n", err);
    }

    return error.Unexpected;
}

// k_sem_* migrated to the curated layer: see zig-import/api/sem.zig

// k_thread_* migrated to the curated layer: see zig-import/api/thread.zig

pub const RegisterSubscriberError = error{
    InvalidChannel,
    InvalidSubscriber,
    TooManySubscribers,
} || UnexpectedError;

pub fn register_subscriber(channel: Channels, evt: *k_event) RegisterSubscriberError!void {
    if (channel >= CHAN_LAST) return error.InvalidChannel;

    const ret: i32 = blk: {
        if (comptime CONFIG_USERSPACE == 1) {
            if (z_syscall_trap()) {
                break :blk @bitCast(arch_syscall_invoke2(channel, @intFromPtr(evt), K_SYSCALL_REGISTER_SUBSCRIBER));
            }
        }

        compiler_barrier();
        break :blk z_impl_register_subscriber(channel, evt);
    };

    switch (ret) {
        SUCCESS => return,
        -EINVAL => unreachable,
        -ENOENT => return error.InvalidSubscriber,
        -ENOMEM => return error.TooManySubscribers,
        else => |err| return unexpectedErrno(err),
    }
}

pub const ReceiveError = error{
    InvalidChannel,
    ReceivingBufferTooSmall,
    BusyChannel,
    TimedOut,
} || UnexpectedError;

pub fn receive(channel: Channels, data: *anyopaque, data_len: usize) ReceiveError!void {
    if (channel >= CHAN_LAST) return error.InvalidChannel;

    const ret: i32 = blk: {
        if (comptime CONFIG_USERSPACE == 1) {
            if (z_syscall_trap()) {
                break :blk @bitCast(arch_syscall_invoke3(channel, @intFromPtr(data), data_len, K_SYSCALL_RECEIVE));
            }
        }

        compiler_barrier();
        break :blk z_impl_receive(channel, data, data_len);
    };

    switch (ret) {
        SUCCESS => return,
        -EINVAL => return error.ReceivingBufferTooSmall,
        -EBUSY => return error.BusyChannel,
        -EAGAIN => return error.TimedOut,
        -EFAULT => unreachable,
        else => |err| return unexpectedErrno(err),
    }
}

// gpio and devicetree access migrated to the curated layer:
// see zig-import/api/gpio.zig and zig-import/api/devicetree.zig
