//! Compile probe for the curated semaphore API.
//!
//! Not loaded on a target -- its job is to exercise every entry point of an
//! area so that `gen/check.sh` can prove the whole surface links against
//! symbols the base image actually exports. Add one of these per curated area.

const z = @import("zephyr");
const c = @import("cimport");

var storage: c.k_sem = undefined;

pub fn probe() callconv(.c) c_int {
    // Userspace construction: the object type is implied by the method.
    const sem = z.Semaphore.alloc(0, 1) catch return 1;

    // Kernel construction over caller-owned storage.
    const owned = z.Semaphore.init(&storage, 1, 4) catch return 2;

    sem.give();
    sem.take(.forever) catch return 3;

    sem.take(.ms(100)) catch |err| switch (err) {
        error.TimedOutOrReset => {},
        error.WouldBlock => return 4,
        error.Unexpected => return 5,
    };

    owned.tryTake() catch |err| switch (err) {
        error.WouldBlock => {},
    };

    owned.take(.seconds(1)) catch return 6;
    owned.take(.us(500)) catch return 7;
    owned.take(.ticks(3)) catch return 8;

    sem.reset();
    if (sem.count() != 0) return 9;

    // The escape hatch, for an area nobody has curated: correct, but C-shaped.
    // check.sh reports this as outstanding curation work.
    if (z.uncurated.k_uptime_ticks() < 0) return 10;

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
