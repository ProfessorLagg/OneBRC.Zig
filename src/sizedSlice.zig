const std = @import("std");
const utils = @import("utils.zig");

pub fn SizedSlice(
    /// Type of items stored in the slice
    comptime T: type,
    /// Type of the length. Must be a primitive unsigned integer
    comptime Tlen: type,
) type {
    comptime {
        const valid: bool = utils.types.isUnsignedInt(T) and utils.types.isPrimitive(Tlen);
        if (!valid) @compileError("Expected primitive unsigned integer, but found " ++ @typeName(Tlen));
    }

    return struct {
        const TSelf = @This();
        const maxLen: Tlen = std.math.maxInt(Tlen);
        ptr: [*]T,
        len: Tlen,

        pub fn fromSlice(s: []const T) TSelf {
            std.debug.assert(s.len <= maxLen);
            return TSelf{
                .ptr = @constCast(s.ptr),
                .len = @intCast(s.len),
            };
        }

        pub fn toSlice(self: *const TSelf) []T {
            var r: []T = undefined;
            r.ptr = @constCast(self.ptr);
            r.len = @intCast(self.len);
            return r;
        }
    };
}
