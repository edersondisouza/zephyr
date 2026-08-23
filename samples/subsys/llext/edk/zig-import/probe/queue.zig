//! Compile probe for the curated queue API.

const z = @import("zephyr");
const c = @import("cimport");

const Item = struct { value: u32 };

var storage: c.k_queue = undefined;
var one: Item = .{ .value = 1 };

pub fn probe() callconv(.c) c_int {
    const q = z.Queue(Item).alloc() catch return 1;
    const owned = z.Queue(Item).init(&storage);

    q.append(&one) catch |err| switch (err) {
        error.OutOfMemory, error.Unexpected => return 2,
    };
    q.prepend(&one) catch return 3;

    // What went in is what comes out, with no cast at the call site.
    const head: *Item = q.peekHead() orelse return 4;
    const tail: *Item = q.peekTail() orelse return 5;
    if (head.value != tail.value) return 6;

    if (q.isEmpty()) return 7;
    const taken: *Item = q.get(.no_wait) orelse return 8;
    if (taken.value != 1) return 9;

    _ = q.get(.ms(10));
    q.cancelWait();

    owned.append(&one) catch return 10;
    if (owned.peekHead() == null) return 11;

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
