//! Compile probe for the curated pipe API.

const z = @import("zephyr");
const c = @import("cimport");

var ring: [8]u8 = undefined;
var owned_ring: [8]u8 = undefined;
var pipe_storage: c.k_pipe = undefined;

pub fn probe() callconv(.c) c_int {
    const p = z.Pipe.alloc(&ring) catch |err| switch (err) {
        error.OutOfMemory, error.UserspaceUnsupported => return 1,
    };
    const owned = z.Pipe.init(&pipe_storage, &owned_ring) catch return 8;

    const wrote: usize = p.write("abcd", .no_wait) catch |err| switch (err) {
        error.TimedOut, error.Cancelled, error.Closed, error.Unexpected => return 2,
    };
    if (wrote != 4) return 3;

    var scratch: [16]u8 = undefined;
    // A slice, not a count: the result is the data.
    const got: []u8 = p.read(&scratch, .no_wait) catch |err| switch (err) {
        error.TimedOut, error.Cancelled, error.Closed, error.Unexpected => return 4,
    };
    if (got.len != 4) return 5;

    _ = owned.write("x", .ms(1)) catch {};
    owned.reset();
    owned.close();

    p.close();
    if (p.write("y", .no_wait)) |_| {
        return 6;
    } else |err| switch (err) {
        error.Closed => {},
        error.TimedOut, error.Cancelled, error.Unexpected => return 7,
    }

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
