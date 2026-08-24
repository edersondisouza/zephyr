//! Curated. The test application's reporting syscall.
//!
//! Same shape as the showcase application's bindings: its own module, its own
//! generated syscall layer beside it, built on the curated layer's public
//! surface. The test set uses the application-as-binding-author path on
//! itself, which is the cheapest way to keep that path honest.

const z = @import("zephyr");
const c = @import("cimport");
const syscall = @import("generated/syscalls.zig");

/// The areas an extension reports on. `TEST_AREA_COUNT` is a bound rather
/// than an area, so it is not here.
pub const Area = enum(c.enum_test_area) {
    semaphore = c.TEST_SEMAPHORE,
    event = c.TEST_EVENT,
    thread = c.TEST_THREAD,
    clock = c.TEST_CLOCK,
    queue = c.TEST_QUEUE,
    mutex = c.TEST_MUTEX,
    condvar = c.TEST_CONDVAR,
};

/// Report the outcome of one area: zero if it passed, otherwise the number of
/// the check that failed.
pub fn report(area: Area, result: c_int) void {
    syscall.report(@intFromEnum(area), result);
}
