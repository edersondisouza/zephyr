//! Curated. Timeouts.
//!
//! `K_MSEC` and its siblings expand through Zephyr's `z_tmcvt_*` chain, which
//! translate-c mistranslates -- it compares the translated `true`/`false`
//! against `0`, so the expression fails to type-check the moment it is
//! instantiated. `K_NO_WAIT` is separately broken, being the compound literal
//! `((k_timeout_t){0})`. Only `K_FOREVER` survived translation.
//!
//! That one gap blocks every timeout-taking API at once, so the conversion is
//! reimplemented here rather than worked around at each call site.

const c = @import("cimport");

pub const Timeout = struct {
    raw: c.k_timeout_t,

    /// Wait indefinitely.
    pub const forever: Timeout = .{ .raw = .{ .ticks = c.K_TICKS_FOREVER } };
    /// Do not wait at all; fail immediately if the operation would block.
    pub const no_wait: Timeout = .{ .raw = .{ .ticks = 0 } };

    pub fn ticks(n: u64) Timeout {
        return .{ .raw = .{ .ticks = @intCast(n) } };
    }
    pub fn ns(n: u64) Timeout {
        return .{ .raw = .{ .ticks = convertCeil(n, c.Z_HZ_ns) } };
    }
    pub fn us(n: u64) Timeout {
        return .{ .raw = .{ .ticks = convertCeil(n, c.Z_HZ_us) } };
    }
    pub fn ms(n: u64) Timeout {
        return .{ .raw = .{ .ticks = convertCeil(n, c.Z_HZ_ms) } };
    }
    pub fn seconds(n: u64) Timeout {
        return ms(n * 1000);
    }
    pub fn minutes(n: u64) Timeout {
        return seconds(n * 60);
    }
    pub fn hours(n: u64) Timeout {
        return minutes(n * 60);
    }

    /// Zephyr rounds timeout conversions up, so that a requested delay is
    /// never shorter than asked for. Matches `k_ms_to_ticks_ceil64` and
    /// friends.
    fn convertCeil(t: u64, comptime from_hz: u64) c.k_ticks_t {
        const to_hz: u64 = c.CONFIG_SYS_CLOCK_TICKS_PER_SEC;
        if (comptime from_hz == to_hz) return @intCast(t);
        return @intCast((t * to_hz + (from_hz - 1)) / from_hz);
    }
};
