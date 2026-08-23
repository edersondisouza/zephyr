//! Curated. Uptime.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");

/// Ticks since boot.
pub fn uptimeTicks() i64 {
    return syscall.k_uptime_ticks();
}

/// Milliseconds since boot, rounded down. This is what `k_uptime_get()`
/// returns; it is an inline over the tick count rather than a syscall of its
/// own, so the conversion happens here.
///
/// Unsigned deliberately. Uptime is never negative, and at -OReleaseSmall a
/// 64-bit divide becomes a libcall rather than an inline multiply -- signed
/// wants __aeabi_ldivmod, which is not linked into a Zephyr image, while
/// unsigned wants __aeabi_uldivmod, which is. An extension can only call what
/// the application exports.
pub fn uptime() u64 {
    const ticks: u64 = @intCast(uptimeTicks());
    const per_second: u64 = c.CONFIG_SYS_CLOCK_TICKS_PER_SEC;
    return ticks * 1000 / per_second;
}
