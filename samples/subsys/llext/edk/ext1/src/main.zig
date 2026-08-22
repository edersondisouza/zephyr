const z = @import("zephyr");
const app = @import("app");
const c = @import("cimport");

const led = z.gpio.Pin.fromDt(z.dt.alias("led1"), "gpios");

pub fn start() callconv(.c) c_int {
    const tick_evt = z.Event.alloc() catch {
        c.printk("[zig][ext1]event alloc failed!\n");
        return 1;
    };

    app.subscribe(.tick, tick_evt) catch unreachable;

    if (!led.isReady()) {
        c.printk("[zig][ext1]LED is not ready!\n");
        return 2;
    }

    led.configure(.output_active) catch {
        c.printk("[zig][ext1]LED configure failed!\n");
        return 3;
    };

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][ext1]Waiting event\n");
        // `.reset` keeps the original behaviour of dropping any tick that
        // arrived while the previous one was being handled. `.{}` alone would
        // consume just the matched event instead, which is the better default
        // for new code.
        _ = tick_evt.wait(c.CHAN_TICK, .{ .consume = false, .reset = true });

        c.printk("[zig][ext1]Got event, reading channel\n");
        app.receive(.tick, &l) catch |err| switch (err) {
            error.BusyChannel => {
                c.printk("[zig][k-ext1]Busy channel! Continuing...\n");
                continue;
            },
            else => unreachable,
        };

        c.printk("[zig][ext1]Read val: %ld\n", l);

        if (l % 2 == 1) {
            c.printk("[zig][ext1]Toggling light on odd value!\n");
            led.toggle() catch {
                c.printk("[zig][ext1]Failed to toggle light!\n");
            };
        }
    }

    return 0;
}

const StartSym = extern struct {
    name: [*:0]const u8,
    addr: *const fn() callconv(.c) c_int,
};

export const start_sym: StartSym linksection(".exported_sym") = .{
    .name = "start",
    .addr = start,
};
