//! Compile probe for the curated event API.
//!
//! Not loaded on a target -- its job is to exercise every entry point of an
//! area so that `gen/check.sh` can prove the whole surface links against
//! symbols the base image actually exports.

const z = @import("zephyr");
const c = @import("cimport");

const EVT_A: u32 = 1 << 0;
const EVT_B: u32 = 1 << 1;

var storage: c.k_event = undefined;

pub fn probe() callconv(.c) c_int {
    const evt = z.Event.alloc() catch return 1;
    const owned = z.Event.init(&storage);

    _ = evt.post(EVT_A);
    _ = evt.set(EVT_A | EVT_B);
    _ = evt.setMasked(EVT_A, EVT_A | EVT_B);
    _ = evt.clear(EVT_B);

    // Every combination the option struct selects, so all four wait syscalls
    // are reachable from this object.
    if (evt.wait(EVT_A, .{}) == null) return 2;
    if (evt.wait(EVT_A, .{ .timeout = .ms(100) }) == null) return 3;
    if (evt.wait(EVT_A | EVT_B, .{ .mode = .all }) == null) return 4;
    if (owned.wait(EVT_A, .{ .consume = false, .reset = true }) == null) return 5;
    if (owned.wait(EVT_A, .{ .mode = .all, .consume = false }) == null) return 6;

    // A runtime-valued option set, to be sure the dispatch still compiles when
    // it cannot be folded.
    var opts: z.Event.WaitOptions = .{};
    opts.mode = if (evt.post(EVT_B) != 0) .all else .any;
    if (owned.wait(EVT_B, opts) == null) return 7;

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
