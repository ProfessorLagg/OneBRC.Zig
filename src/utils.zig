const builtin = @import("builtin");
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

    fn copyBytes_generic(noalias dst: []u8, noalias src: []const u8) void {
        std.debug.assert(dst.len >= src.len);
        for (dst[0..src.len], src) |*d, s| d.* = s;
    }

    fn copyBytes_x86_64(noalias dst: []u8, noalias src: []const u8) void {
        comptime if (builtin.cpu.arch != .x86_64) @compileError("This function only works for x86_64 targets. You probably want copyBytes_generic");
        // https://www.felixcloutier.com/x86/rep:repe:repz:repne:repnz
        asm volatile ( // NO FOLD
            "rep movsb"
            :
            : [src] "{rsi}" (src.ptr),
              [dst] "{rdi}" (dst.ptr),
              [len] "{rcx}" (src.len),
        );
    }
    const copyBytes: @TypeOf(copyBytes_generic) = switch (builtin.cpu.arch) {
        .x86_64 => copyBytes_x86_64,
        else => copyBytes_generic,
    };
    /// Copies all of src into dst starting at index 0
    pub fn copy(comptime T: type, noalias dst: []T, noalias src: []const T) void {
        std.debug.assert(dst.len >= src.len);

        const dst_u8: []u8 = std.mem.sliceAsBytes(dst);
        const src_u8: []const u8 = std.mem.sliceAsBytes(src);
        copyBytes(dst_u8, src_u8);
    }
    pub fn clone(comptime T: type, allocator: std.mem.Allocator, a: []const T) ![]T {
        const result: []T = try allocator.alloc(T, a.len);
        copy(T, result, a);
        return result;
    }
};
