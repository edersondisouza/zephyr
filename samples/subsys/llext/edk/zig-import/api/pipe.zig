//! Curated. Byte-stream pipes.
//!
//! Two things here are unlike the rest of the curated layer, and both come
//! from the C interface rather than from taste.
//!
//! `k_pipe_read` and `k_pipe_write` return a *count*, not a status. A transfer
//! that moves fewer bytes than asked for has succeeded, and only a transfer
//! that moves none reports a failure: `z_impl_k_pipe_read` ends with
//! `rc = buf.used ? buf.used : -EAGAIN`. So a short result is the ordinary
//! outcome of a timeout expiring partway through, and callers that need all of
//! it have to loop.
//!
//! And a pipe's ring buffer belongs to the caller. There is no allocating
//! constructor as there is for message queues, so the buffer is a slice the
//! extension owns and has to keep alive for as long as the pipe.
//!
//! ## Kernel extensions only, for now
//!
//! A userspace extension cannot create a pipe. `z_vrfy_k_pipe_init` guards
//! itself with `K_SYSCALL_OBJ`, which requires the object to be initialised
//! *already* -- so initialising a fresh one is rejected. Every other init
//! verifier in the kernel uses `K_SYSCALL_OBJ_INIT` (any state) or
//! `K_SYSCALL_OBJ_NEVER_INIT` (must be fresh); pipe is the only one that asks
//! for the state its own call is there to produce. It works for a statically
//! defined pipe, which is marked initialised at build time, and a dynamically
//! loaded userspace extension cannot have one of those.
//!
//! Reaching it anyway is a kernel oops, which halts the board and says
//! "used before initialization". The constructors check first and return
//! `UserspaceUnsupported` instead.

const c = @import("cimport");
const syscall = @import("../generated/syscalls.zig");
const errno = @import("errno.zig");
const isUserContext = @import("thread.zig").isUserContext;
const Timeout = @import("timeout.zig").Timeout;

pub const Pipe = struct {
    /// The underlying kernel object. Public so that an extension can reach a
    /// `zephyr.uncurated.k_pipe_*` call this API has not curated yet.
    raw: *c.struct_k_pipe,

    pub const TransferError = error{
        /// The timeout expired without moving a single byte. Moving *some* of
        /// them is a short transfer, not this.
        TimedOut,
        /// `reset` interrupted the transfer.
        Cancelled,
        /// The pipe has been closed.
        Closed,
    } || errno.UnexpectedError;

    pub const InitError = error{
        /// See the note at the top of this file: k_pipe_init cannot be
        /// reached from userspace at all. Kernel extensions are unaffected.
        UserspaceUnsupported,
    };

    pub const AllocError = error{OutOfMemory} || InitError;

    /// Allocate a pipe from the calling thread's resource pool, over a ring
    /// buffer the caller provides and keeps alive.
    pub fn alloc(buffer: []u8) AllocError!Pipe {
        if (isUserContext()) return error.UserspaceUnsupported;
        const obj = syscall.k_object_alloc(c.K_OBJ_PIPE) orelse return error.OutOfMemory;
        const self: Pipe = .{ .raw = @ptrCast(@alignCast(obj)) };
        syscall.k_pipe_init(self.raw, buffer.ptr, buffer.len);
        return self;
    }

    /// Initialise a pipe in storage the caller already owns.
    pub fn init(storage: *c.struct_k_pipe, buffer: []u8) InitError!Pipe {
        if (isUserContext()) return error.UserspaceUnsupported;
        const self: Pipe = .{ .raw = storage };
        syscall.k_pipe_init(self.raw, buffer.ptr, buffer.len);
        return self;
    }

    /// Read into `into`, returning the part of it that was filled.
    ///
    /// The result is the data, so it is a slice rather than a count. It can be
    /// shorter than `into` without anything being wrong.
    pub fn read(self: Pipe, into: []u8, timeout: Timeout) TransferError![]u8 {
        const ret = syscall.k_pipe_read(self.raw, into.ptr, into.len, timeout.raw);
        if (ret >= 0) return into[0..@intCast(ret)];
        return switch (ret) {
            -c.EAGAIN => error.TimedOut,
            -c.ECANCELED => error.Cancelled,
            -c.EPIPE => error.Closed,
            else => |err| errno.unexpected(err),
        };
    }

    /// Write `data`, returning how much of it was taken.
    ///
    /// A count rather than a slice, because what a caller wants to know here
    /// is how much of *their* buffer was consumed, not which bytes moved.
    pub fn write(self: Pipe, data: []const u8, timeout: Timeout) TransferError!usize {
        const ret = syscall.k_pipe_write(self.raw, data.ptr, data.len, timeout.raw);
        if (ret >= 0) return @intCast(ret);
        return switch (ret) {
            -c.EAGAIN => error.TimedOut,
            -c.ECANCELED => error.Cancelled,
            -c.EPIPE => error.Closed,
            else => |err| errno.unexpected(err),
        };
    }

    /// Discard what is buffered and interrupt anyone waiting, whose transfer
    /// fails with `Cancelled`.
    pub fn reset(self: Pipe) void {
        syscall.k_pipe_reset(self.raw);
    }

    /// Close the pipe. Readers drain what is left and then get `Closed`;
    /// writers get it immediately.
    pub fn close(self: Pipe) void {
        syscall.k_pipe_close(self.raw);
    }
};
