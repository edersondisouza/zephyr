//! Curated. Packing a value into a machine word.
//!
//! Several Zephyr APIs carry one caller value through a pointer-sized slot and
//! hand it back later: a thread's three entry-point arguments, a stack's
//! `stack_data_t` entries, a timer's user data. The C interface calls all of
//! them `void *` or `uintptr_t` and leaves the casting to the caller at both
//! ends, which is two chances to disagree with yourself.
//!
//! These do the casting once, driven by the type, so the value that comes back
//! is the type that went in. Anything wider than a word is a compile error
//! naming itself, rather than a silent truncation.

/// Pack a value into a word, the way the C caller would have cast it.
pub fn pack(value: anytype) usize {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(value),
        .optional => if (value) |v| @intFromPtr(v) else 0,
        .int, .comptime_int => @intCast(value),
        .@"enum" => @intCast(@intFromEnum(value)),
        .bool => @intFromBool(value),
        .void => 0,
        else => @compileError("a value carried through a machine word must fit " ++
            "in one, and " ++ @typeName(T) ++ " does not; pass a pointer to it instead"),
    };
}

/// Recover a value packed by `pack`.
pub fn unpack(comptime T: type, word: usize) T {
    return switch (@typeInfo(T)) {
        .pointer => @ptrFromInt(word),
        .optional => if (word == 0) null else @ptrFromInt(word),
        .int => @intCast(word),
        .@"enum" => @enumFromInt(word),
        .bool => word != 0,
        .void => {},
        else => @compileError("unsupported packed type " ++ @typeName(T)),
    };
}
