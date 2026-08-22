//! Curated. Devicetree access.
//!
//! Zephyr's devicetree API is macros over identifiers that the build system
//! generates. translate-c turns those into top-level *declarations* of the
//! cimport namespace, so reaching them means `@hasDecl` and `@field` on a
//! type -- not `@hasField`, which compiles fine and reports that every
//! property is absent. That mistake is invisible: `propOr` quietly returns
//! its default, and a pin comes back configured active-high on a board that
//! wired it active-low.
//!
//! Node ids are comptime strings here, the same way they are comptime tokens
//! in C.

const std = @import("std");
const c = @import("cimport");

/// Whether the devicetree defines a generated constant.
pub fn has(comptime name: []const u8) bool {
    return @hasDecl(c, name);
}

/// A generated devicetree constant, with whatever type translate-c gave it.
pub fn get(comptime name: []const u8) @TypeOf(@field(c, name)) {
    return @field(c, name);
}

/// The node id an alias points at: `alias("led0")`.
pub fn alias(comptime name: []const u8) []const u8 {
    return get("DT_N_ALIAS_" ++ name);
}

/// The node id a nodelabel points at: `nodelabel("gpio0")`.
pub fn nodelabel(comptime name: []const u8) []const u8 {
    return get("DT_N_NODELABEL_" ++ name);
}

pub fn hasProp(comptime node_id: []const u8, comptime name: []const u8) bool {
    return has(node_id ++ "_P_" ++ name);
}

pub fn prop(comptime node_id: []const u8, comptime name: []const u8) @TypeOf(get(node_id ++ "_P_" ++ name)) {
    return get(node_id ++ "_P_" ++ name);
}

/// The node id at index `idx` of a phandle array property.
pub fn phandleByIdx(
    comptime node_id: []const u8,
    comptime name: []const u8,
    comptime idx: u32,
) []const u8 {
    return get(std.fmt.comptimePrint("{s}_P_{s}_IDX_{d}_PH", .{ node_id, name, idx }));
}

/// One cell of a phandle array entry, e.g. the `pin` cell of `gpios`.
pub fn cellByIdx(
    comptime node_id: []const u8,
    comptime name: []const u8,
    comptime idx: u32,
    comptime cell: []const u8,
) @TypeOf(get(std.fmt.comptimePrint("{s}_P_{s}_IDX_{d}_VAL_{s}", .{ node_id, name, idx, cell }))) {
    return get(std.fmt.comptimePrint("{s}_P_{s}_IDX_{d}_VAL_{s}", .{ node_id, name, idx, cell }));
}

/// One cell of a phandle array entry, or `default` when the binding did not
/// declare it. A `gpios` entry without a flags cell is the common case.
pub fn cellByIdxOr(
    comptime T: type,
    comptime node_id: []const u8,
    comptime name: []const u8,
    comptime idx: u32,
    comptime cell: []const u8,
    comptime default: T,
) T {
    const decl = std.fmt.comptimePrint("{s}_P_{s}_IDX_{d}_VAL_{s}", .{ node_id, name, idx, cell });
    return if (has(decl)) get(decl) else default;
}

/// The `struct device` a node was built into. Devices are named after their
/// dependency ordinal rather than their path.
pub fn device(comptime node_id: []const u8) *const c.struct_device {
    // `comptime` is load-bearing: every input here is comptime-known, but
    // without it the ordinal is an ordinary const when this is called from a
    // function body, and comptimePrint cannot use it. Which is to say these
    // helpers must work anywhere, not only at file scope.
    const symbol = comptime std.fmt.comptimePrint(
        "__device_dts_ord_{d}",
        .{get(node_id ++ "_ORD")},
    );
    return &@field(c, symbol);
}
