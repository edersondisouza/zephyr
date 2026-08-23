//! Hand-written support code for the generated syscall layer (tier 0).
//!
//! Everything here is machinery that `generated/syscalls.zig` needs and that a
//! generator has no business synthesising: the `svc` trampolines themselves,
//! the user-context test that decides whether to trap, and the two marshalling
//! helpers that stand in for the C stubs' `union { uintptr_t x; T val; }`.
//!
//! This is the *only* file outside `generated/` allowed to contain
//! `arch_syscall_invoke`; `gen/check.sh` enforces that.

const c = @import("cimport");

// ---- svc trampolines -------------------------------------------------------
//
// One per arity, matching Zephyr's arch/arm/include/syscall.h. The call id
// travels in r6, arguments in r0-r4 and r12. Argument registers are inputs, so
// only the registers above the arity are clobbered.

pub fn arch_syscall_invoke0(call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
        : .{ .r8 = true, .memory = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true });
}

pub fn arch_syscall_invoke1(arg1: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
        : .{ .r8 = true, .memory = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true });
}

pub fn arch_syscall_invoke2(arg1: usize, arg2: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
        : .{ .r8 = true, .memory = true, .r2 = true, .r3 = true, .r12 = true });
}

pub fn arch_syscall_invoke3(arg1: usize, arg2: usize, arg3: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
        : .{ .r8 = true, .memory = true, .r3 = true, .r12 = true });
}

pub fn arch_syscall_invoke4(arg1: usize, arg2: usize, arg3: usize, arg4: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
        : .{ .r8 = true, .memory = true, .r12 = true });
}

pub fn arch_syscall_invoke5(arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
        : .{ .r8 = true, .memory = true, .r12 = true });
}

pub fn arch_syscall_invoke6(arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize, call_id: usize) usize {
    return asm volatile ("svc %[svid]\n"
        : [ret] "={r0}" (-> usize),
        : [svid] "i" (c._SVC_CALL_SYSTEM_CALL),
          [call_id] "{r6}" (call_id),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
          // r5, not r12. r12 is `ip`, which Zephyr's own trampoline lists as
          // a clobber -- passing the sixth argument there means the kernel
          // reads whatever r5 happened to hold. k_thread_create is the only
          // arity-6 syscall the samples reach, and only from userspace, which
          // is why this survived until something ran it.
          [arg6] "{r5}" (arg6),
        : .{ .r8 = true, .memory = true, .r12 = true });
}

// ---- trap decision ---------------------------------------------------------

pub fn arch_is_user_context() bool {
    if (comptime c.CONFIG_CPU_CORTEX_M == 1) {
        var value: u32 = undefined;

        asm volatile ("mrs %[value], IPSR\n"
            : [value] "=r" (value),
            :
            : .{});

        // Non-zero IPSR means we are in an exception, which is never userspace.
        if (value != 0) {
            return false;
        }
    }

    return c.z_arm_thread_is_in_user_mode();
}

pub fn z_syscall_trap() bool {
    return arch_is_user_context();
}

pub inline fn compiler_barrier() void {
    asm volatile (""
        :
        :
        : .{ .memory = true });
}

// ---- marshalling helpers ---------------------------------------------------

/// Zig equivalent of the generated `union { uintptr_t x; T val; }` punning.
pub inline fn cast(v: anytype) usize {
    const T = @TypeOf(v);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(v),
        .optional => @intFromPtr(v),
        .bool => @intFromBool(v),
        .@"enum" => @intCast(@intFromEnum(v)),
        .int => |i| if (i.signedness == .signed)
            @bitCast(@as(isize, @intCast(v)))
        else
            @as(usize, @intCast(v)),
        .comptime_int => @as(usize, v),
        else => @compileError("unsupported syscall argument type " ++ @typeName(T)),
    };
}

/// Zig equivalent of the generated `return (T) arch_syscall_invokeN(...)`.
pub inline fn from(comptime T: type, v: usize) T {
    return switch (@typeInfo(T)) {
        .pointer => @ptrFromInt(v),
        .optional => @ptrFromInt(v),
        .bool => v != 0,
        .@"enum" => @enumFromInt(@as(u32, @truncate(v))),
        .int => |i| if (i.signedness == .signed)
            @truncate(@as(isize, @bitCast(v)))
        else
            @truncate(v),
        .void => {},
        else => @compileError("unsupported syscall return type " ++ @typeName(T)),
    };
}
