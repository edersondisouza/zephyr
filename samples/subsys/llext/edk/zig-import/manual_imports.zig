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

pub fn k_event_init(event: *struct_k_event) void {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            _ = arch_syscall_invoke1(@intFromPtr(event), K_SYSCALL_K_EVENT_INIT);
            return;
        }
    }

    compiler_barrier();
    z_impl_k_event_init(event);
}

pub fn k_event_wait(event: *struct_k_event, events: u32, reset: bool, timeout: k_timeout_t) u32 {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            const ticks: u64 = @bitCast(timeout.ticks);
            const hi: u32 = @intCast(ticks >> 32);
            const lo: u32 = @intCast(ticks & 0xffffffff);

            return arch_syscall_invoke5(@intFromPtr(event), events, @intFromBool(reset), lo, hi, K_SYSCALL_K_EVENT_WAIT);
        }
    }

    compiler_barrier();
    return z_impl_k_event_wait(event, events, reset, timeout);
}

pub fn k_sem_init(sem: *struct_k_sem, initial_count: u32, limit: u32) callconv(.c) i32 {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            return @bitCast(arch_syscall_invoke3(@intFromPtr(sem), initial_count, limit, K_SYSCALL_K_SEM_INIT));
        }
    }

    compiler_barrier();
    return z_impl_k_sem_init(sem, initial_count, limit);
}

pub fn k_sem_give(sem: *struct_k_sem) void {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            _ = arch_syscall_invoke1(@intFromPtr(sem), K_SYSCALL_K_SEM_GIVE);
            return;
        }
    }

    compiler_barrier();
    z_impl_k_sem_give(sem);
}

pub fn k_sem_take(sem: *struct_k_sem, timeout: k_timeout_t) i32 {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            const ticks: u64 = @bitCast(timeout.ticks);
            const hi: u32 = @intCast(ticks >> 32);
            const lo: u32 = @intCast(ticks & 0xffffffff);

            return @bitCast(arch_syscall_invoke3(@intFromPtr(sem), hi, lo, K_SYSCALL_K_SEM_GIVE));
        }
    }

    compiler_barrier();
    return z_impl_k_sem_take(sem, timeout);
}

pub fn k_thread_stack_alloc(size: usize, flags: i32) !*k_thread_stack_t {
    var ret: usize = undefined;

    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            ret = arch_syscall_invoke2(size, @bitCast(flags), K_SYSCALL_K_THREAD_STACK_ALLOC);
            return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
        }
    }

    compiler_barrier();
    ret = @intFromPtr(z_impl_k_thread_stack_alloc(size, flags));

    return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
}

pub fn k_thread_create(new_thread: *struct_k_thread, stack: *k_thread_stack_t, stack_size: usize, entry: k_thread_entry_t, p1: ?*anyopaque, p2: ?*anyopaque, p3: ?*anyopaque, prio: i32, options: u32, delay: k_timeout_t) !*struct_k_thread {
    var ret: usize = undefined;

    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            const ticks: u64 = @bitCast(delay.ticks);
            const hi: u32 = @intCast(ticks >> 32);
            const lo: u32 = @intCast(ticks & 0xffffffff);

            const more = [_]usize{
                @intFromPtr(p2),
                @intFromPtr(p3),
                @bitCast(prio),
                options,
                hi,
                lo
            };

            ret = arch_syscall_invoke6(@intFromPtr(new_thread), @intFromPtr(stack), stack_size,
                @intFromPtr(entry), @intFromPtr(p1), @intFromPtr(&more), K_SYSCALL_K_THREAD_STACK_ALLOC);
            return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
        }
    }

    compiler_barrier();
    ret = @intFromPtr(z_impl_k_thread_create(new_thread, stack, stack_size, entry, p1, p2, p3,
            prio, options, delay));

    return if (ret == 0) error.OutOfMemory else @ptrFromInt(ret);
}

pub fn register_subscriber(channel: Channels, evt: *k_event) i32 {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            return @bitCast(arch_syscall_invoke2(channel, @intFromPtr(evt), K_SYSCALL_REGISTER_SUBSCRIBER));
        }
    }

    compiler_barrier();
    return z_impl_register_subscriber(channel, evt);
}

pub fn receive(channel: Channels, data: ?*anyopaque, data_len: usize) i32 {
    if (comptime CONFIG_USERSPACE == 1) {
        if (z_syscall_trap()) {
            return @bitCast(arch_syscall_invoke3(channel, @intFromPtr(data), data_len, K_SYSCALL_RECEIVE));
        }
    }

    compiler_barrier();
    return z_impl_receive(channel, data, data_len);
}
