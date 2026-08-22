//! Curated. GPIO.
//!
//! Two things get decided here that the C interface leaves loose.
//!
//! The configuration word is a 32-bit bag of bits with a documented layout,
//! which is exactly a Zig packed struct. Named combinations stay available as
//! declarations, so `.output_active` and `.{ .input = true, .pull_up = true }`
//! both work and neither can be spelled wrong.
//!
//! The interrupt combinations are a closed set of nine, not a free bitmask;
//! mixing them is meaningless, so they are an enum.

const std = @import("std");
const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const dt = @import("devicetree.zig");

// ---- configuration ---------------------------------------------------------

/// The `gpio_flags_t` bit layout from drivers/gpio.h, spelled out.
pub const Flags = packed struct(u32) {
    /// The pin is asserted when the line is low.
    active_low: bool = false,
    /// Drive only one direction; pair with `line_open_drain`.
    single_ended: bool = false,
    /// With `single_ended`: open drain rather than open source.
    line_open_drain: bool = false,
    _reserved_3: u1 = 0,
    pull_up: bool = false,
    pull_down: bool = false,
    /// Allow this pin's interrupt to wake the system.
    int_wakeup: bool = false,
    _reserved_7: u9 = 0,
    input: bool = false,
    output: bool = false,
    /// Drive low on configure.
    output_init_low: bool = false,
    /// Drive high on configure.
    output_init_high: bool = false,
    /// Interpret the init level logically, honouring `active_low`.
    output_init_logical: bool = false,
    int_disable: bool = false,
    int_enable: bool = false,
    int_levels_logical: bool = false,
    int_edge: bool = false,
    int_low_0: bool = false,
    int_high_1: bool = false,
    _reserved_27: u5 = 0,

    /// Neither driven nor read.
    pub const disconnected: Flags = .{};
    // No `input`/`output` presets: Zig forbids a declaration shadowing a
    // field, and `.{ .input = true }` is no worse to write.
    /// Output, driven to its physical low level.
    pub const output_low: Flags = .{ .output = true, .output_init_low = true };
    /// Output, driven to its physical high level.
    pub const output_high: Flags = .{ .output = true, .output_init_high = true };
    /// Output, driven to its *logical* inactive level.
    pub const output_inactive: Flags = .{
        .output = true,
        .output_init_low = true,
        .output_init_logical = true,
    };
    /// Output, driven to its *logical* active level.
    pub const output_active: Flags = .{
        .output = true,
        .output_init_high = true,
        .output_init_logical = true,
    };
    pub const open_drain: Flags = .{ .single_ended = true, .line_open_drain = true };
    pub const open_source: Flags = .{ .single_ended = true };

    pub fn merge(self: Flags, other: Flags) Flags {
        return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
    }

    fn raw(self: Flags) c.gpio_flags_t {
        return @bitCast(self);
    }

    comptime {
        // The layout above is hand-transcribed from a header, so check it
        // against the constants translate-c produced rather than trusting the
        // transcription. A wrong bit here misconfigures a pin silently.
        const cases = .{
            .{ disconnected, c.GPIO_DISCONNECTED },
            .{ Flags{ .input = true }, c.GPIO_INPUT },
            .{ Flags{ .output = true }, c.GPIO_OUTPUT },
            .{ output_low, c.GPIO_OUTPUT_LOW },
            .{ output_high, c.GPIO_OUTPUT_HIGH },
            .{ output_inactive, c.GPIO_OUTPUT_INACTIVE },
            .{ output_active, c.GPIO_OUTPUT_ACTIVE },
            .{ open_drain, c.GPIO_OPEN_DRAIN },
            .{ open_source, c.GPIO_OPEN_SOURCE },
            .{ Flags{ .active_low = true }, c.GPIO_ACTIVE_LOW },
            .{ Flags{ .pull_up = true }, c.GPIO_PULL_UP },
            .{ Flags{ .pull_down = true }, c.GPIO_PULL_DOWN },
            .{ Flags{ .int_wakeup = true }, c.GPIO_INT_WAKEUP },
        };
        for (cases) |case| {
            if (@as(u32, @bitCast(case[0])) != @as(u32, case[1])) {
                @compileError("Flags layout disagrees with drivers/gpio.h");
            }
        }
    }
};

/// When a pin should raise an interrupt. Zephyr builds these out of five
/// flag bits, but only these combinations mean anything.
pub const Interrupt = enum {
    disable,
    edge_rising,
    edge_falling,
    edge_both,
    level_low,
    level_high,
    /// Logical variants honour the pin's `active_low`.
    edge_to_active,
    edge_to_inactive,
    level_active,
    level_inactive,

    fn raw(self: Interrupt) c.gpio_flags_t {
        return switch (self) {
            .disable => c.GPIO_INT_DISABLE,
            .edge_rising => c.GPIO_INT_EDGE_RISING,
            .edge_falling => c.GPIO_INT_EDGE_FALLING,
            .edge_both => c.GPIO_INT_EDGE_BOTH,
            .level_low => c.GPIO_INT_LEVEL_LOW,
            .level_high => c.GPIO_INT_LEVEL_HIGH,
            .edge_to_active => c.GPIO_INT_EDGE_TO_ACTIVE,
            .edge_to_inactive => c.GPIO_INT_EDGE_TO_INACTIVE,
            .level_active => c.GPIO_INT_LEVEL_ACTIVE,
            .level_inactive => c.GPIO_INT_LEVEL_INACTIVE,
        };
    }
};

// Error sets follow what each call documents, rather than one set for the
// whole driver API. The documented sets differ by more than they look: a
// port-level access can only fail two ways, while configuring an interrupt
// can fail six. Sharing one set both advertises failures a call cannot
// produce and, worse, drops the ones it can -- EBUSY and ENOSYS from
// gpio_pin_interrupt_configure have no home in a set built for
// gpio_pin_configure.

/// What every call in the driver API can report.
pub const AccessError = error{
    /// The controller reported an I/O failure.
    IOError,
    /// The operation would block, and was asked not to.
    WouldBlock,
} || errno.UnexpectedError;

/// The driver does not implement this operation at all.
pub const Unimplemented = error{NotImplemented};

/// The pin number is outside what the controller has, or the requested
/// configuration is not one it can do.
pub const BadPin = error{ NotSupported, InvalidPin };

fn accessError(ret: c_int) AccessError!void {
    return switch (ret) {
        0 => {},
        -c.EIO => error.IOError,
        -c.EWOULDBLOCK => error.WouldBlock,
        else => |err| errno.unexpected(err),
    };
}

// ---- pins ------------------------------------------------------------------

pub const Pin = struct {
    /// The underlying `gpio_dt_spec`. Public so that an extension can reach a
    /// `zephyr.uncurated.gpio_*` call this API has not curated yet.
    raw: c.struct_gpio_dt_spec,

    /// The pin a devicetree node's phandle array points at, e.g.
    ///
    ///     const led = Pin.fromDt(z.dt.alias("led0"), "gpios");
    pub fn fromDt(comptime node_id: []const u8, comptime prop: []const u8) Pin {
        return fromDtByIdx(node_id, prop, 0);
    }

    pub fn fromDtByIdx(
        comptime node_id: []const u8,
        comptime prop: []const u8,
        comptime idx: u32,
    ) Pin {
        // Built at comptime so that this reads the same whether it is called
        // at file scope or inside a function: the devicetree constants come
        // through as c_int, which only coerces to the spec's narrower fields
        // while they are still comptime values.
        return comptime .{ .raw = .{
            .port = dt.device(dt.phandleByIdx(node_id, prop, idx)),
            .pin = dt.cellByIdx(node_id, prop, idx, "pin"),
            // The flags cell is optional; a node without one is active-high
            // and push-pull.
            .dt_flags = dt.cellByIdxOr(c.gpio_dt_flags_t, node_id, prop, idx, "flags", 0),
        } };
    }

    /// Whether the controller behind this pin has finished initialising.
    pub fn isReady(self: Pin) bool {
        return syscall.device_is_ready(self.raw.port);
    }

    /// Configure the pin. The devicetree's own flags -- polarity in
    /// particular -- are merged in, so `.output_active` means active
    /// according to the board, not according to the wiring.
    pub const ConfigureError = BadPin || AccessError;

    pub fn configure(self: Pin, flags: Flags) ConfigureError!void {
        const combined: c.gpio_flags_t = flags.raw() | self.raw.dt_flags;
        return switch (syscall.gpio_pin_configure(self.raw.port, self.raw.pin, combined)) {
            -c.ENOTSUP => error.NotSupported,
            -c.EINVAL => error.InvalidPin,
            else => |ret| accessError(ret),
        };
    }

    pub const InterruptError = BadPin || Unimplemented || AccessError || error{
        /// The pin's interrupt is already in use.
        Busy,
    };

    pub fn configureInterrupt(self: Pin, mode: Interrupt) InterruptError!void {
        const combined: c.gpio_flags_t = mode.raw() | self.raw.dt_flags;
        return switch (syscall.gpio_pin_interrupt_configure(self.raw.port, self.raw.pin, combined)) {
            -c.ENOTSUP => error.NotSupported,
            -c.EINVAL => error.InvalidPin,
            -c.EBUSY => error.Busy,
            -c.ENOSYS => error.NotImplemented,
            else => |ret| accessError(ret),
        };
    }

    pub const ReadConfigError = error{InvalidPin} || Unimplemented || AccessError;

    /// The pin's current configuration, as the driver understands it.
    pub fn config(self: Pin) ReadConfigError!Flags {
        var flags: c.gpio_flags_t = undefined;
        switch (syscall.gpio_pin_get_config(self.raw.port, self.raw.pin, &flags)) {
            -c.EINVAL => return error.InvalidPin,
            -c.ENOSYS => return error.NotImplemented,
            else => |ret| try accessError(ret),
        }
        return @bitCast(flags);
    }

    /// Read the pin's logical level: true means active, honouring polarity.
    pub fn get(self: Pin) AccessError!bool {
        var value: c.gpio_port_value_t = undefined;
        try accessError(syscall.gpio_port_get_raw(self.raw.port, &value));
        const physical = (value & self.mask()) != 0;
        return physical != self.activeLow();
    }

    /// Drive the pin to a logical level, honouring polarity.
    pub fn set(self: Pin, active: bool) AccessError!void {
        const physical = active != self.activeLow();
        return accessError(if (physical)
            syscall.gpio_port_set_bits_raw(self.raw.port, self.mask())
        else
            syscall.gpio_port_clear_bits_raw(self.raw.port, self.mask()));
    }

    pub fn toggle(self: Pin) AccessError!void {
        return accessError(syscall.gpio_port_toggle_bits(self.raw.port, self.mask()));
    }

    /// The port this pin belongs to, for whole-port operations.
    pub fn port(self: Pin) Port {
        return .{ .raw = self.raw.port };
    }

    fn mask(self: Pin) c.gpio_port_pins_t {
        return @as(c.gpio_port_pins_t, 1) << @truncate(self.raw.pin);
    }

    fn activeLow(self: Pin) bool {
        return (self.raw.dt_flags & c.GPIO_ACTIVE_LOW) != 0;
    }
};

// ---- whole ports -----------------------------------------------------------

pub const Port = struct {
    /// The underlying controller device.
    raw: *const c.struct_device,

    pub const Direction = struct {
        inputs: c.gpio_port_pins_t,
        outputs: c.gpio_port_pins_t,
    };

    pub fn isReady(self: Port) bool {
        return syscall.device_is_ready(self.raw);
    }

    /// Physical levels of every pin, without polarity applied.
    pub fn getRaw(self: Port) AccessError!c.gpio_port_value_t {
        var value: c.gpio_port_value_t = undefined;
        try accessError(syscall.gpio_port_get_raw(self.raw, &value));
        return value;
    }

    pub fn setMaskedRaw(
        self: Port,
        pin_mask: c.gpio_port_pins_t,
        value: c.gpio_port_value_t,
    ) AccessError!void {
        return accessError(syscall.gpio_port_set_masked_raw(self.raw, pin_mask, value));
    }

    pub fn setBitsRaw(self: Port, pins: c.gpio_port_pins_t) AccessError!void {
        return accessError(syscall.gpio_port_set_bits_raw(self.raw, pins));
    }

    pub fn clearBitsRaw(self: Port, pins: c.gpio_port_pins_t) AccessError!void {
        return accessError(syscall.gpio_port_clear_bits_raw(self.raw, pins));
    }

    pub fn toggleBits(self: Port, pins: c.gpio_port_pins_t) AccessError!void {
        return accessError(syscall.gpio_port_toggle_bits(self.raw, pins));
    }

    /// Which of `pin_mask`'s pins are configured as inputs and as outputs.
    /// Reported through two out-parameters in C.
    pub const DirectionError = Unimplemented || AccessError;

    pub fn direction(self: Port, pin_mask: c.gpio_port_pins_t) DirectionError!Direction {
        var inputs: c.gpio_port_pins_t = undefined;
        var outputs: c.gpio_port_pins_t = undefined;
        switch (syscall.gpio_port_get_direction(self.raw, pin_mask, &inputs, &outputs)) {
            -c.ENOSYS => return error.NotImplemented,
            else => |ret| try accessError(ret),
        }
        return .{ .inputs = inputs, .outputs = outputs };
    }

    /// The interrupt the controller has pending, if the driver reports one.
    /// ENOSYS is the only failure this call documents.
    pub fn pendingInterrupt(self: Port) (Unimplemented || errno.UnexpectedError)!c_int {
        const ret = syscall.gpio_get_pending_int(self.raw);
        if (ret >= 0) return ret;
        return switch (ret) {
            -c.ENOSYS => error.NotImplemented,
            else => |err| errno.unexpected(err),
        };
    }
};
