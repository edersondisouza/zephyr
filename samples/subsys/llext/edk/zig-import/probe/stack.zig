//! Compile probe for the curated stack API.

const z = @import("zephyr");

const Item = struct { value: u32 };
var one: Item = .{ .value = 1 };

pub fn probe() callconv(.c) c_int {
    // A stack of pointers, and a stack of plain integers.
    const pointers = z.Stack(*Item).alloc(4) catch |err| switch (err) {
        error.OutOfMemory, error.ZeroCapacity, error.TooLarge => return 1,
    };
    const numbers = z.Stack(u32).alloc(2) catch return 2;

    pointers.push(&one) catch |err| switch (err) {
        error.Full => return 3,
    };
    const back: *Item = pointers.pop(.no_wait) catch |err| switch (err) {
        error.WouldBlock, error.TimedOut, error.Unexpected => return 4,
    };
    if (back.value != 1) return 5;

    numbers.push(7) catch return 6;
    if ((numbers.pop(.ms(1)) catch return 7) != 7) return 8;

    if (z.Stack(u32).alloc(0)) |_| {
        return 9;
    } else |err| switch (err) {
        error.ZeroCapacity => {},
        error.OutOfMemory, error.TooLarge => return 10,
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
