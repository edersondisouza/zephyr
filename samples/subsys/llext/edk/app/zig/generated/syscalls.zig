//! TIER 0 -- RAW SYSCALLS. GENERATED FILE, DO NOT EDIT.
//!
//! Regenerate with `gen/regen.sh` whenever the EDK's syscalls change.
//! One faithful wrapper per syscall the extension API can reach: C ABI
//! signatures lifted from cimport.zig, C error codes, no ergonomics.
//!
//! Extensions should not import this directly -- use the curated `zephyr`
//! API. It is reachable as `zephyr.uncurated` for syscalls nobody has
//! curated yet, and `gen/check.sh` reports every such use as curation work
//! still to do.
//!
//! Provenance: frdm_mcxn947_mcxn947_cpu0, 3 syscalls from app_api.h

const c = @import("cimport");
const p = @import("zephyr").abi;

/// app_api.h :: K_SYSCALL_PUBLISH, arity 3
pub fn publish(arg_channel: c.enum_Channels, arg_data: ?*anyopaque, arg_data_len: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_channel), p.cast(arg_data), p.cast(arg_data_len), c.K_SYSCALL_PUBLISH));
        }
    }
    p.compiler_barrier();
    return c.z_impl_publish(arg_channel, arg_data, arg_data_len);
}

/// app_api.h :: K_SYSCALL_RECEIVE, arity 3
pub fn receive(arg_channel: c.enum_Channels, arg_data: ?*anyopaque, arg_data_len: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_channel), p.cast(arg_data), p.cast(arg_data_len), c.K_SYSCALL_RECEIVE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_receive(arg_channel, arg_data, arg_data_len);
}

/// app_api.h :: K_SYSCALL_REGISTER_SUBSCRIBER, arity 2
pub fn register_subscriber(arg_channel: c.enum_Channels, arg_evt: [*c]c.struct_k_event) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_channel), p.cast(arg_evt), c.K_SYSCALL_REGISTER_SUBSCRIBER));
        }
    }
    p.compiler_barrier();
    return c.z_impl_register_subscriber(arg_channel, arg_evt);
}
