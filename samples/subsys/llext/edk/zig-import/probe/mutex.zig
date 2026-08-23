//! Compile probe for the curated mutex and condition variable APIs.

const z = @import("zephyr");
const c = @import("cimport");

var mutex_storage: c.k_mutex = undefined;
var condvar_storage: c.k_condvar = undefined;

pub fn probe() callconv(.c) c_int {
    const m = z.Mutex.alloc() catch return 1;
    const owned = z.Mutex.init(&mutex_storage);

    m.lock(.forever) catch |err| switch (err) {
        error.WouldBlock, error.TimedOut, error.Unexpected => return 2,
    };
    m.unlock() catch |err| switch (err) {
        error.NotOwner, error.NotLocked, error.Unexpected => return 3,
    };

    m.tryLock() catch |err| switch (err) {
        error.WouldBlock => return 4,
    };
    m.unlock() catch return 5;

    owned.lock(.ms(10)) catch return 6;
    owned.unlock() catch return 7;

    const cv = z.Condvar.alloc() catch return 8;
    const cv_owned = z.Condvar.init(&condvar_storage);

    m.lock(.forever) catch return 9;
    cv.wait(m, .ms(1)) catch |err| switch (err) {
        error.TimedOut => {},
        error.Unexpected => return 10,
    };
    m.unlock() catch return 11;

    cv.signal();
    // broadcast reports how many threads it woke, not a status.
    const woken: u32 = cv_owned.broadcast();
    if (woken != 0) return 12;

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
