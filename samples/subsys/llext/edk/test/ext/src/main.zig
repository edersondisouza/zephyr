//! Tests for the curated Zephyr bindings.
//!
//! Built twice, unchanged, and loaded into two contexts. That is the whole
//! design: the curated code is identical either way, but a userspace
//! extension reaches Zephyr through the `svc` marshalling in the generated
//! layer while a kernel one calls `z_impl_*` directly. Every binding bug found
//! so far lived in the marshalling and compiled perfectly.
//!
//! Each area returns zero, or the number of the check that failed. Numbers
//! rather than messages because the result crosses a syscall boundary as an
//! int; the application turns them back into a failed ztest case.

const z = @import("zephyr");
const app = @import("app");
const c = @import("cimport");

const EVT_A: u32 = 1 << 0;
const EVT_B: u32 = 1 << 1;

// ---- semaphores ------------------------------------------------------------

fn testSemaphore() c_int {
    const sem = z.Semaphore.alloc(0, 2) catch return 1;
    if (sem.count() != 0) return 2;

    sem.give();
    if (sem.count() != 1) return 3;

    // A take that dispatched to the give handler instead -- which is exactly
    // what the hand-written wrapper used to do -- would leave this at 2.
    sem.take(.forever) catch return 4;
    if (sem.count() != 0) return 5;

    if (sem.tryTake()) |_| {
        return 6; // succeeded on an empty semaphore
    } else |err| switch (err) {
        error.WouldBlock => {},
    }

    // A real timeout has to elapse, and has to say that is what happened.
    const before = z.uptime();
    if (sem.take(.ms(50))) |_| {
        return 7;
    } else |err| switch (err) {
        error.TimedOutOrReset => {},
        error.WouldBlock => return 8,
        error.Unexpected => return 9,
    }
    if (z.uptime() - before < 40) return 10;

    sem.give();
    sem.give();
    if (sem.count() != 2) return 11;
    sem.reset();
    if (sem.count() != 0) return 12;

    // The limit is checked before the kernel is asked.
    if (z.Semaphore.alloc(3, 2)) |_| {
        return 13;
    } else |err| switch (err) {
        error.InvalidCount => {},
        else => return 14,
    }

    return 0;
}

// ---- events ----------------------------------------------------------------

fn testEvent() c_int {
    const evt = z.Event.alloc() catch return 1;

    if (evt.wait(EVT_A, .{ .timeout = .no_wait }) != null) return 2;

    _ = evt.post(EVT_A);
    const matched = evt.wait(EVT_A, .{ .timeout = .no_wait }) orelse return 3;
    if (matched & EVT_A == 0) return 4;

    // The default consumes what it matched, so there is nothing left.
    if (evt.wait(EVT_A, .{ .timeout = .no_wait }) != null) return 5;

    // Without consuming, one event satisfies two waits.
    _ = evt.post(EVT_A);
    _ = evt.wait(EVT_A, .{ .consume = false, .timeout = .no_wait }) orelse return 6;
    _ = evt.wait(EVT_A, .{ .consume = false, .timeout = .no_wait }) orelse return 7;

    // `.all` needs every requested bit, not any of them.
    _ = evt.set(EVT_A);
    if (evt.wait(EVT_A | EVT_B, .{
        .mode = .all,
        .consume = false,
        .timeout = .no_wait,
    }) != null) return 8;

    _ = evt.post(EVT_B);
    _ = evt.wait(EVT_A | EVT_B, .{
        .mode = .all,
        .consume = false,
        .timeout = .no_wait,
    }) orelse return 9;

    _ = evt.clear(EVT_A | EVT_B);
    if (evt.wait(EVT_A | EVT_B, .{ .timeout = .no_wait }) != null) return 10;

    // `.reset` clears everything *before* waiting, so an event posted first is
    // thrown away. This is the behaviour that makes it the wrong default.
    _ = evt.post(EVT_A);
    if (evt.wait(EVT_A, .{
        .consume = false,
        .reset = true,
        .timeout = .no_wait,
    }) != null) return 11;

    return 0;
}

// ---- threads ---------------------------------------------------------------

var counter: u32 = 0;

fn bump(target: *u32, by: u32) void {
    target.* += by;
}

fn testThread() c_int {
    // A userspace extension can only create userspace threads.
    const flags: u32 = if (z.isUserContext())
        c.K_USER | c.K_INHERIT_PERMS
    else
        c.K_INHERIT_PERMS;

    const opts: z.Thread.Options = .{
        .stack_size = 2048,
        .priority = 3,
        .flags = flags,
    };

    counter = 0;
    const ran = z.Thread.spawn(bump, .{ &counter, @as(u32, 7) }, opts) catch return 1;
    ran.join(.forever) catch return 2;
    // Both that it ran at all, and that its arguments survived the three
    // opaque slots they travel through.
    if (counter != 7) return 3;
    ran.destroy() catch return 4;

    // `.manual` must not schedule it.
    counter = 0;
    var manual_opts = opts;
    manual_opts.start = .manual;
    const manual = z.Thread.spawn(bump, .{ &counter, @as(u32, 3) }, manual_opts) catch return 5;
    _ = z.sleep(.ms(20));
    if (counter != 0) return 6;
    manual.start();
    manual.join(.forever) catch return 7;
    if (counter != 3) return 8;
    manual.destroy() catch return 9;

    // `.after` schedules it without any further prompting.
    counter = 0;
    var delayed_opts = opts;
    delayed_opts.start = .{ .after = .ms(20) };
    const delayed = z.Thread.spawn(bump, .{ &counter, @as(u32, 5) }, delayed_opts) catch return 10;
    delayed.join(.forever) catch return 11;
    if (counter != 5) return 12;
    delayed.destroy() catch return 13;

    return 0;
}

// ---- clock and timeouts ----------------------------------------------------

fn testClock() c_int {
    const ms_before = z.uptime();
    const ticks_before = z.uptimeTicks();

    _ = z.sleep(.ms(50));

    const ms_elapsed = z.uptime() - ms_before;
    if (ms_elapsed < 45) return 2;
    if (ms_elapsed > 500) return 3;

    // The timeout constructors are reimplemented in the curated layer, because
    // translate-c mistranslates Zephyr's conversion macros. Check that 50 ms
    // really is 50 ms worth of ticks at this clock rate.
    const ticks_elapsed = z.uptimeTicks() - ticks_before;
    const ticks_expected = @divFloor(50 * @as(i64, c.CONFIG_SYS_CLOCK_TICKS_PER_SEC), 1000);
    if (ticks_elapsed < ticks_expected) return 4;

    // Sleeping the whole period leaves nothing over.
    if (z.sleep(.ms(10)) != 0) return 5;

    return 0;
}

// ---- queues ----------------------------------------------------------------

const Item = struct { value: u32 };

// Deliberately uninitialised: an initialised mutable global lands in .data,
// and LLVM puts .data among the .rodata* sections, which llext refuses to load
// -- see "Initialised mutable globals" in ../../zig-import/README.md.
var items: [3]Item = undefined;

fn testQueue() c_int {
    items = .{ .{ .value = 10 }, .{ .value = 20 }, .{ .value = 30 } };

    const q = z.Queue(Item).alloc() catch return 1;

    if (!q.isEmpty()) return 2;
    if (q.get(.no_wait) != null) return 3;

    q.append(&items[0]) catch return 4;
    q.append(&items[1]) catch return 5;
    if (q.isEmpty()) return 6;

    // Peeking does not take.
    if ((q.peekHead() orelse return 7).value != 10) return 8;
    if ((q.peekTail() orelse return 9).value != 20) return 10;
    if ((q.peekHead() orelse return 11).value != 10) return 12;

    // Append then get is first in, first out.
    if ((q.get(.no_wait) orelse return 13).value != 10) return 14;
    if ((q.get(.no_wait) orelse return 15).value != 20) return 16;
    if (!q.isEmpty()) return 17;

    // Prepend puts it in front of what is already queued.
    q.append(&items[0]) catch return 18;
    q.prepend(&items[2]) catch return 19;
    if ((q.get(.no_wait) orelse return 20).value != 30) return 21;
    if ((q.get(.no_wait) orelse return 22).value != 10) return 23;

    // A timed get on an empty queue waits, then gives up.
    const before = z.uptime();
    if (q.get(.ms(30)) != null) return 24;
    if (z.uptime() - before < 25) return 25;

    return 0;
}

// ---- entry -----------------------------------------------------------------

pub fn start() callconv(.c) c_int {
    app.report(.semaphore, testSemaphore());
    app.report(.event, testEvent());
    app.report(.thread, testThread());
    app.report(.clock, testClock());
    app.report(.queue, testQueue());
    return 0;
}

const StartSym = extern struct {
    name: [*:0]const u8,
    addr: *const fn () callconv(.c) c_int,
};

export const start_sym: StartSym linksection(".exported_sym") = .{
    .name = "start",
    .addr = start,
};
