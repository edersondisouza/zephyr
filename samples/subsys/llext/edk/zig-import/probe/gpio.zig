//! Compile probe for the curated GPIO API.

const z = @import("zephyr");
const c = @import("cimport");

const led = z.gpio.Pin.fromDt(z.dt.alias("led0"), "gpios");
const led1 = z.gpio.Pin.fromDtByIdx(z.dt.alias("led1"), "gpios", 0);

comptime {
    // The devicetree marks this LED active-low; losing that flag drives the
    // board inverted, which a blink sample cannot show you.
    if (led.raw.dt_flags & c.GPIO_ACTIVE_LOW == 0) {
        @compileError("led0 should have picked up GPIO_ACTIVE_LOW from the devicetree");
    }
}

pub fn probe() callconv(.c) c_int {
    if (!led.isReady()) return 1;

    led.configure(.output_active) catch |err| switch (err) {
        error.NotSupported, error.InvalidPin,
        error.IOError, error.WouldBlock, error.Unexpected,
        => return 2,
    };
    led.configure(.{ .output = true, .output_init_low = true }) catch return 3;
    led1.configure(.{ .input = true, .pull_up = true }) catch return 4;

    led.set(true) catch return 5;
    // Exhaustive, no else: a port-level access documents exactly these, and
    // this stops compiling if the set ever widens or narrows.
    led.toggle() catch |err| switch (err) {
        error.IOError, error.WouldBlock, error.Unexpected => return 6,
    };
    if (led.get() catch return 7) return 8;

    _ = led.config() catch return 9;

    // Six of them, including the EBUSY and ENOSYS a shared driver-wide error
    // set used to swallow into Unexpected.
    led1.configureInterrupt(.edge_to_active) catch |err| switch (err) {
        error.Busy,
        error.NotImplemented,
        error.NotSupported,
        error.InvalidPin,
        error.IOError,
        error.WouldBlock,
        error.Unexpected,
        => return 10,
    };
    led1.configureInterrupt(.disable) catch return 11;

    const port = led.port();
    if (!port.isReady()) return 12;
    _ = port.getRaw() catch return 13;
    port.setBitsRaw(0x1) catch return 14;
    port.clearBitsRaw(0x1) catch return 15;
    port.setMaskedRaw(0x3, 0x2) catch return 16;
    port.toggleBits(0x1) catch return 17;
    const dir = port.direction(0xff) catch return 18;
    if (dir.inputs == dir.outputs and dir.inputs != 0) return 19;
    _ = port.pendingInterrupt() catch return 20;

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
