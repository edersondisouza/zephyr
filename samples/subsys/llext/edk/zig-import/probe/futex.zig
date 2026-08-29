//! Compile probe for the curated futex API.

const z = @import("zephyr");
const c = @import("cimport");

var storage: c.k_futex = undefined;

pub fn probe() callconv(.c) c_int {
    const f = z.Futex.at(&storage);

    // The fast path is plain atomics, no syscall in sight.
    f.store(0);
    if (f.load() != 0) return 2;
    if (f.fetchAdd(1) != 0) return 3;
    if (f.load() != 1) return 4;
    if (f.compareExchange(1, 2) != null) return 5;
    if (f.compareExchange(1, 3)) |actual| {
        if (actual != 2) return 6;
    } else return 7;

    // The slow path: the value no longer matches, so there is nothing to
    // wait for and the kernel says so rather than sleeping.
    f.wait(999, .no_wait) catch |err| switch (err) {
        error.Changed => {},
        error.TimedOut, error.AccessDenied, error.NotRegistered, error.Unexpected => return 8,
    };

    const woken: u32 = f.wake(true) catch |err| switch (err) {
        error.AccessDenied, error.NotRegistered, error.Unexpected => return 9,
    };
    if (woken != 0) return 10;

    return 0;
}

const StartSym = extern struct {
    name: [*:0]const u8,
    addr: *const fn () callconv(.c) c_int,
};

export const start_sym: StartSym linksection(".exported_sym") = .{
    .name = "probe",
    .addr = probe,
};
