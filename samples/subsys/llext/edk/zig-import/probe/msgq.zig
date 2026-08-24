//! Compile probe for the curated message queue API.

const z = @import("zephyr");

const Tick = struct { seq: u32, value: i32 };

pub fn probe() callconv(.c) c_int {
    const q = z.MessageQueue(Tick).alloc(4) catch return 1;

    if (q.capacity() != 4) return 2;
    if (q.available() != 4) return 3;
    if (q.used() != 0) return 4;
    if (q.peek() != null) return 5;
    if (q.peekAt(0) != null) return 6;

    q.put(.{ .seq = 1, .value = -1 }, .no_wait) catch |err| switch (err) {
        error.FullOrPurged, error.TimedOut, error.Unexpected => return 7,
    };
    q.putFront(.{ .seq = 0, .value = 0 }) catch |err| switch (err) {
        error.Full => return 8,
    };

    // Messages come back by value, with no cast and no out-parameter.
    const first: Tick = q.get(.no_wait) catch |err| switch (err) {
        error.EmptyOrPurged, error.TimedOut, error.Unexpected => return 9,
    };
    if (first.seq != 0) return 10;

    const peeked: Tick = q.peek() orelse return 11;
    if (peeked.seq != 1) return 12;

    q.purge();
    if (q.used() != 0) return 13;

    _ = q.get(.ms(1)) catch {};

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
