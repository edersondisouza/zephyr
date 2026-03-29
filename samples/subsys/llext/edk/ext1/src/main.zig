const c = @import("cimport.zig");

pub fn start() callconv(.c) c_int {
    const tick_evt: *c.k_event = c.k_object_alloc(c.K_OBJ_EVENT, c.k_event) catch {
        c.printk("[zig][ext1]k_object_alloc failed!\n");
        return 1;
    };

    c.k_event_init(tick_evt);

    _ = c.register_subscriber(c.CHAN_TICK, tick_evt);

    while (true) {
        var l: usize = undefined;

        c.printk("[zig][ext1]Waiting event\n");
        _ = c.k_event_wait(tick_evt, c.CHAN_TICK, true, c.K_FOREVER);

        c.printk("[zig][ext1]Got event, reading channel\n");
        _ = c.receive(c.CHAN_TICK, &l, @sizeOf(@TypeOf(l)));
        c.printk("[zig][ext1]Read val: %ld\n", l);
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
