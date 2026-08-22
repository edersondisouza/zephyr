const z = @import("zephyr");
const c = @import("cimport");
const std = @import("std");

const STACKSIZE: usize = 512;
const PRIORITY: i32 = 2;

var my_sem: z.Semaphore = undefined;

const led = c.GPIO_DT_SPEC_GET(c.DT_ALIAS("led0"), "gpios");

fn tick_sub() void {
    const tick_evt = z.Event.alloc() catch {
        c.printk("[zig][k-ext1]event alloc failed!\n");
        return;
    };

    c.register_subscriber(c.CHAN_TICK, tick_evt.raw) catch unreachable;

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

    if (!c.gpio_is_ready_dt(&led)) {
        c.printk("[zig][k-ext1]LED is not ready!\n");
        return 4;
    }

    c.gpio_pin_configure_dt(&led, c.GPIO_OUTPUT_ACTIVE) catch {
        c.printk("[zig][k-ext1]gpio_pin_configure_dt failed!\n");
        return 5;
    };

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][k-ext1]Waiting sem\n");
        my_sem.take(.forever) catch unreachable;

        c.printk("[zig][k-ext1]Got sem, reading channel\n");
        c.receive(c.CHAN_TICK, &l, @sizeOf(@TypeOf(l))) catch |err| switch (err) {
            error.BusyChannel => {
                c.printk("[zig][k-ext1]Busy channel! Continuing...\n");
                continue;
            },
            else => unreachable,
        };
        c.printk("[zig][k-ext1]Read val: %ld\n", l);

        c.printk("[zig][k-ext1]Toggling light!\n");
        c.gpio_pin_toggle_dt(&led) catch {
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
