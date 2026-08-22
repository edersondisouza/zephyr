//! Compile probe for the curated thread API.
//!
//! Not loaded on a target -- its job is to exercise every entry point of an
//! area so that `gen/check.sh` can prove the whole surface links against
//! symbols the base image actually exports.

const z = @import("zephyr");
const c = @import("cimport");

const Context = struct { ticks: u32 };
var context: Context = .{ .ticks = 0 };

fn bare() void {
    z.yield();
    _ = z.sleep(.ms(10));
    _ = z.usleep(500);
    z.busyWait(5);
}

fn withContext(ctx: *Context) void {
    ctx.ticks += 1;
}

/// Three arguments of three different shapes, to check the packing both ways.
fn withThree(ctx: *Context, count: u32, flag: bool) void {
    if (flag) ctx.ticks += count;
}

fn raw(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {}

pub fn probe() callconv(.c) c_int {
    if (!z.isPreemptible()) return 1;

    const a = z.Thread.spawn(bare, .{}, .{ .stack_size = 512, .priority = 2 }) catch return 2;
    const b = z.Thread.spawn(withContext, .{&context}, .{
        .stack_size = 512,
        .priority = 3,
        .flags = c.K_INHERIT_PERMS,
        .start = .{ .after = .ms(50) },
    }) catch return 3;
    const three = z.Thread.spawn(withThree, .{ &context, @as(u32, 7), true }, .{
        .stack_size = 512,
        .priority = 6,
    }) catch return 12;
    three.abort();
    const d = z.Thread.spawnRaw(raw, .{ null, null, null }, .{
        .stack_size = 512,
        .priority = 4,
    }) catch return 4;

    // Acquire the resources now, run it later.
    const later = z.Thread.spawn(bare, .{}, .{
        .stack_size = 512,
        .priority = 5,
        .start = .manual,
    }) catch return 11;
    later.start();

    const me = z.Thread.current();
    if (me.priority() != 0) me.setPriority(0);

    a.@"suspend"();
    a.@"resume"();
    a.wakeup();

    var buf: [32]u8 = undefined;
    b.setName("probe") catch |err| switch (err) {
        error.NotSupported => {},
        else => return 5,
    };
    _ = b.nameInto(&buf) catch |err| switch (err) {
        error.NotSupported => "",
        else => return 6,
    };

    _ = me.stackUnused() catch return 7;

    d.abort();
    d.join(.forever) catch return 8;
    d.destroy() catch return 9;

    a.join(.ms(100)) catch |err| switch (err) {
        error.TimedOut, error.WouldBlock => {},
        else => return 10,
    };
    b.join(.no_wait) catch {};

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
