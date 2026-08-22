//! The example in README.md, compiled.
//!
//! A documented example that nobody builds rots. This is that example, with
//! only the surrounding declarations added, so an API change that invalidates
//! the README breaks the build instead.

const z = @import("zephyr");

const TICK: u32 = 1 << 0;
const Context = struct { count: u32 };
var context: Context = .{ .count = 0 };

fn worker(ctx: *Context) void {
    ctx.count += 1;
}

pub fn probe() callconv(.c) c_int {
    const led = z.gpio.Pin.fromDt(z.dt.alias("led0"), "gpios");
    led.configure(.output_active) catch return 1;

    const sem = z.Semaphore.alloc(0, 1) catch return 2;
    const evt = z.Event.alloc() catch return 3;

    _ = z.Thread.spawn(worker, .{&context}, .{ .stack_size = 512, .priority = 2 }) catch return 4;

    if (evt.wait(TICK, .{ .timeout = .ms(100) })) |matched| {
        if (matched & TICK != 0) led.toggle() catch return 5;
        sem.take(.forever) catch return 6;
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
