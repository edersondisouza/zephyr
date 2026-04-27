const c = @import("cimport.zig");
const std = @import("std");

const STACKSIZE: c_int = 512;
const PRIORITY: u32 = 2;

pub const K_FOREVER = c.k_timeout_t{.ticks = -1};
pub const K_NO_WAIT = c.k_timeout_t{};

var my_sem: *c.k_sem = undefined;

const led = c.GPIO_DT_SPEC_GET(c.DT_ALIAS("led0"), "gpios");

pub fn tick_sub(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const tick_evt = c.k_object_alloc(c.K_OBJ_EVENT, c.k_event) catch {
        c.printk("[zig][k-ext1]k_object_alloc failed!\n");
        return;
    };

    c.k_event_init(tick_evt);

    c.register_subscriber(c.CHAN_TICK, tick_evt) catch unreachable;

    while (true) {
        c.printk("[zig][k-ext1]Waiting event\n");
        _ = c.k_event_wait(tick_evt, c.CHAN_TICK, true, K_FOREVER);
        c.printk("[zig][k-ext1]Got event, giving sem\n");
        c.k_sem_give(my_sem);
    }
}

pub fn start() callconv(.c) c_int {
    my_sem = c.k_object_alloc(c.K_OBJ_EVENT, c.k_sem) catch {
        c.printk("[zig][k-ext1]k_object_alloc 1 failed!\n");
        return 2;
    };

    c.k_sem_init(my_sem, 0, 1) catch unreachable;

    const sub_stack: *c.k_thread_stack_t = c.k_thread_stack_alloc(STACKSIZE, 0) catch {
        c.printk("[zig][k-ext1]k_thread_stack_alloc failed!\n");
        return 3;
    };

    const sub_thread = c.k_object_alloc(c.K_OBJ_THREAD, c.k_thread) catch {
        c.printk("[zig][k-ext1]k_object_alloc 2 failed!\n");
        return 4;
    };

    _ = c.k_thread_create(sub_thread, sub_stack, STACKSIZE, tick_sub, null, null, null, PRIORITY,
        c.K_INHERIT_PERMS, K_NO_WAIT) catch {
        c.printk("[zig][k-ext1]k_thread_create failed!\n");
        return 5;
    };

    if (!c.gpio_is_ready_dt(&led)) {
        c.printk("[zig][k-ext1]LED is not ready!\n");
        return 6;
    }

    c.gpio_pin_configure_dt(&led, c.GPIO_OUTPUT_ACTIVE) catch {
        c.printk("[zig][k-ext1]gpio_pin_configure_dt failed!\n");
        return 7;
    };

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][k-ext1]Waiting sem\n");
        c.k_sem_take(my_sem, K_FOREVER) catch unreachable;

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
