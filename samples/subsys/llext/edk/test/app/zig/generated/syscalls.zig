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
//! Provenance: frdm_mcxn947_mcxn947_cpu0, 1 syscalls from test_api.h

const c = @import("cimport");
const p = @import("zephyr").abi;

/// test_api.h :: K_SYSCALL_REPORT, arity 2
pub fn report(arg_area: c.enum_test_area, arg_result: c_int) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_area), p.cast(arg_result), c.K_SYSCALL_REPORT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_report(arg_area, arg_result);
}
