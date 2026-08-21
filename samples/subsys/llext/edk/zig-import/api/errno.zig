//! Curated. Shared fallback for return codes a wrapper does not model.
//!
//! Every curated API maps the errno values its syscall documents onto named
//! Zig errors. Anything else is a kernel contract we did not anticipate, so it
//! surfaces as `error.Unexpected` rather than being silently swallowed.

const c = @import("cimport");
const builtin = @import("builtin");

pub const UnexpectedError = error{Unexpected};

pub fn unexpected(err: c_int) UnexpectedError {
    if (builtin.mode == .Debug) {
        c.printk("[zephyr] unexpected errno %d\n", err);
    }
    return error.Unexpected;
}
