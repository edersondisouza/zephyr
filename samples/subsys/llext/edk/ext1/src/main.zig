const c = @import("cimport.zig");

const led = c.GPIO_DT_SPEC_GET(c.DT_ALIAS("led1"), "gpios");

pub fn start() callconv(.c) c_int {
    const tick_evt: *c.k_event = c.k_object_alloc(c.K_OBJ_EVENT, c.k_event) catch {
        c.printk("[zig][ext1]k_object_alloc failed!\n");
        return 1;
    };

    c.k_event_init(tick_evt);

    c.register_subscriber(c.CHAN_TICK, tick_evt) catch unreachable;

    if (!c.gpio_is_ready_dt(&led)) {
        c.printk("[zig][ext1]LED is not ready!\n");
        return 2;
    }

    c.gpio_pin_configure_dt(&led, c.GPIO_OUTPUT_ACTIVE) catch {
        c.printk("[zig][ext1]gpio_pin_configure_dt failed!\n");
        return 3;
    };

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][ext1]Waiting event\n");
        _ = c.k_event_wait(tick_evt, c.CHAN_TICK, true, c.K_FOREVER);

        c.printk("[zig][ext1]Got event, reading channel\n");
        c.receive(c.CHAN_TICK, &l, @sizeOf(@TypeOf(l))) catch |err| switch (err) {
            error.BusyChannel => {
                c.printk("[zig][k-ext1]Busy channel! Continuing...\n");
                continue;
            },
            else => unreachable,
        };

        c.printk("[zig][ext1]Read val: %ld\n", l);

        if (l % 2 == 1) {
            c.printk("[zig][ext1]Toggling light on odd value!\n");
            c.gpio_pin_toggle_dt(&led) catch {
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
