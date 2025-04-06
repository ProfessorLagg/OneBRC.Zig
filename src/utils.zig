const std = @import("std");

pub const mem = struct {
    /// Copy all of source into dest at position 0.
    /// dst.len must be >= src.len.
    /// If the slices overlap, dst.ptr must be <= src.ptr.
    pub fn copyForwards(comptime T: type, noalias dst: []T, noalias src: []const T) void {
        std.debug.assert(dst.len >= src.len);
        std.debug.assert(@intFromPtr(dst.ptr) <= @intFromPtr(src.ptr));
        for (dst[0..src.len], src) |*d, s| d.* = s;
    }
};
