//! Curated. Futexes.
//!
//! A futex is the one kernel object whose value the caller manipulates
//! directly. The point of it is that the uncontended case never enters the
//! kernel at all: you change the value with an atomic instruction, and only
//! call `wait` or `wake` when a thread actually has to block or be released.
//!
//! Zephyr's own `atomic_*` helpers do not survive translate-c -- they come
//! from `atomic_builtin.h`, whose bodies are compiler intrinsics -- so this is
//! the area where that stops mattering. Zig has atomics of its own, and they
//! are a better binding than a wrapper around the C ones would have been:
//! `load`, `store`, `compareExchange` and `fetchAdd` below are ordinary Zig
//! builtins on the same word, with the memory ordering spelled out.
//!
//! ## An extension cannot own a contended futex
//!
//! The atomics work on any `k_futex` the extension can write, which is the
//! whole fast path. `wait` and `wake` need more: `k_futex_find_data` requires
//! the address to be a registered `K_OBJ_FUTEX`, and that registration is
//! emitted by `gen_kobject_list.py` scanning statically declared futexes at
//! build time. A dynamically loaded extension has none, and cannot allocate
//! one either -- `k_object_alloc` refuses the type outright:
//!
//!     case K_OBJ_FUTEX:  /* Lives in user memory */
//!         LOG_ERR("forbidden object type '%s' requested");
//!
//! which is deliberate: a futex allocated from the kernel heap would not be in
//! user memory, and being in user memory is the point of it.
//!
//! So there is no constructor here, only `at`. An extension can use the
//! atomics on its own storage today, and `wait`/`wake` the moment an
//! application hands it the address of a futex the build registered.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const Timeout = @import("timeout.zig").Timeout;

/// The futex word. `atomic_t` is a `long`, which is 32 bits on this target;
/// taking it from the C type rather than assuming keeps that honest.
pub const Value = c.atomic_t;

pub const Futex = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_futex_*` call this API has not curated yet.
    raw: *c.struct_k_futex,

    pub const WaitError = error{
        /// The value was not `expected`, so there was nothing to wait for.
        /// This is the ordinary outcome of losing the race, not a failure.
        Changed,
        /// The waiting period expired.
        TimedOut,
        /// The caller cannot write the futex word.
        AccessDenied,
        /// The kernel does not know this address as a futex.
        NotRegistered,
    } || errno.UnexpectedError;

    pub const WakeError = error{
        AccessDenied,
        NotRegistered,
    } || errno.UnexpectedError;

    /// The futex at this address.
    ///
    /// There is no allocating constructor, and cannot be: see the note at the
    /// top of this file. The atomics work on any storage the extension can
    /// write; `wait` and `wake` additionally need the address to have been
    /// registered by the build, and report `NotRegistered` when it was not.
    pub fn at(storage: *c.struct_k_futex) Futex {
        return .{ .raw = storage };
    }

    // ---- the fast path: no syscall ----------------------------------------

    pub fn load(self: Futex) Value {
        return @atomicLoad(Value, &self.raw.val, .seq_cst);
    }

    pub fn store(self: Futex, value: Value) void {
        @atomicStore(Value, &self.raw.val, value, .seq_cst);
    }

    /// Set the word to `desired` if it is still `expected`. Returns null on
    /// success, or the value that was actually there.
    pub fn compareExchange(self: Futex, expected: Value, desired: Value) ?Value {
        return @cmpxchgStrong(Value, &self.raw.val, expected, desired, .seq_cst, .seq_cst);
    }

    /// Add to the word, returning what was there before.
    pub fn fetchAdd(self: Futex, delta: Value) Value {
        return @atomicRmw(Value, &self.raw.val, .Add, delta, .seq_cst);
    }

    // ---- the slow path: the kernel ----------------------------------------

    /// Sleep until woken, but only while the word still reads `expected`.
    ///
    /// The check and the sleep happen together in the kernel, which is the
    /// whole reason this call exists: testing the value yourself and then
    /// sleeping would race with the writer.
    pub fn wait(self: Futex, expected: Value, timeout: Timeout) WaitError!void {
        return switch (syscall.k_futex_wait(self.raw, @intCast(expected), timeout.raw)) {
            0 => {},
            -c.EAGAIN => error.Changed,
            -c.ETIMEDOUT => error.TimedOut,
            -c.EACCES => error.AccessDenied,
            -c.EINVAL => error.NotRegistered,
            else => |err| errno.unexpected(err),
        };
    }

    /// Wake one waiter, or every waiter. Returns how many were woken -- a
    /// count, not a status.
    pub fn wake(self: Futex, all: bool) WakeError!u32 {
        const ret = syscall.k_futex_wake(self.raw, all);
        if (ret >= 0) return @intCast(ret);
        return switch (ret) {
            -c.EACCES => error.AccessDenied,
            -c.EINVAL => error.NotRegistered,
            else => |err| errno.unexpected(err),
        };
    }
};
