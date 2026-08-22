const z = @import("zephyr");
const app = @import("app");
const c = @import("cimport");
const std = @import("std");

const STACKSIZE: usize = 512;
const PRIORITY: i32 = 2;

var my_sem: z.Semaphore = undefined;

const led = z.gpio.Pin.fromDt(z.dt.alias("led0"), "gpios");

fn tick_sub() void {
    const tick_evt = z.Event.alloc() catch {
        c.printk("[zig][k-ext1]event alloc failed!\n");
        return;
    };

    app.subscribe(.tick, tick_evt) catch unreachable;

    while (true) {
        c.printk("[zig][k-ext1]Waiting event\n");
        _ = tick_evt.wait(c.CHAN_TICK, .{ .consume = false, .reset = true });
        c.printk("[zig][k-ext1]Got event, giving sem\n");
        my_sem.give();
    }
}

pub fn start() callconv(.c) c_int {
    my_sem = z.Semaphore.alloc(0, 1) catch {
        c.printk("[zig][k-ext1]semaphore alloc failed!\n");
        return 2;
    };

    _ = z.Thread.spawn(tick_sub, .{}, .{
        .stack_size = STACKSIZE,
        .priority = PRIORITY,
        .flags = c.K_INHERIT_PERMS,
    }) catch {
        c.printk("[zig][k-ext1]thread spawn failed!\n");
        return 3;
    };

    if (!led.isReady()) {
        c.printk("[zig][k-ext1]LED is not ready!\n");
        return 4;
    }

    led.configure(.output_active) catch {
        c.printk("[zig][k-ext1]LED configure failed!\n");
        return 5;
    };

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][k-ext1]Waiting sem\n");
        my_sem.take(.forever) catch unreachable;

        c.printk("[zig][k-ext1]Got sem, reading channel\n");
        app.receive(.tick, &l) catch |err| switch (err) {
            error.BusyChannel => {
                c.printk("[zig][k-ext1]Busy channel! Continuing...\n");
                continue;
            },
            else => unreachable,
        };
        c.printk("[zig][k-ext1]Read val: %ld\n", l);

        c.printk("[zig][k-ext1]Toggling light!\n");
        led.toggle() catch {
            c.printk("[zig][k-ext1]Failed to toggle light!\n");
        };
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
