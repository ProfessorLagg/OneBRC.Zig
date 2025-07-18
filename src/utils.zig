const builtin = @import("builtin");
const std = @import("std");
const _asm = @import("_asm.zig");

pub const mem = struct {
    /// Copies as much from `src` as will fit into `dst`. Returns the number of bytes copied;
    pub fn copyBytes(noalias src: []const u8, noalias dst: []u8) usize {
        const l: usize = @min(src.len, dst.len);
        _asm.repmovsb(dst.ptr, src.ptr, l);
        return l;
    }

    pub fn copy(comptime T: type, noalias src: []const T, noalias dst: []T) usize {
        const srcbytes: []const u8 = std.mem.sliceAsBytes(src);
        const dstbytes: []u8 = std.mem.sliceAsBytes(dst);
        const copySize: usize = copyBytes(srcbytes, dstbytes);
        std.debug.assert(copySize % @sizeOf(T) == 0);
        return copySize / @sizeOf(T);
    }

    /// Resizes `buf` to `new_len`. Returns `true` if pointers where invalidated
    pub fn resize(comptime T: type, allocator: std.mem.Allocator, noalias buf: *[]T, new_len: usize) !bool {
        if (allocator.resize(buf.*, new_len)) {
            buf.len = new_len;
            return false;
        }

        buf.* = allocator.remap(buf.*, new_len) orelse b: {
            const new: []T = try allocator.alloc(T, new_len);
            const clen: usize = copy(T, buf.*, new);
            std.debug.assert(clen == buf.len);
            break :b new;
        };

        return false;
    }
};

pub const math = struct {
    pub fn fastIntParse(comptime T: type, noalias numstr: []const u8) T {
        comptime {
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int) @compileError("Expected signed integer, but found " ++ @typeName(T));
            if (ti.int.signedness != .signed) @compileError("Expected signed integer, but found " ++ @typeName(T));
        }

        std.debug.assert(numstr.len > 0);
        const isNegative: bool = numstr[0] == '-';
        const isNegativeInt: T = @intFromBool(isNegative);

        var result: T = 0;
        var m: T = 1;

        var i: isize = @as(isize, @intCast(numstr.len)) - 1;
        while (i >= isNegativeInt) : (i -= 1) {
            const ci: T = @intCast(numstr[@as(usize, @bitCast(i))]);
            const valid: bool = ci >= 48 and ci <= 57;
            const validInt: T = @intFromBool(valid);
            const invalidInt: T = @intFromBool(!valid);
            result += validInt * ((ci - 48) * m); // '0' = 48
            m = (m * 10 * validInt) + (m * invalidInt);
        }

        const sign: T = (-1 * isNegativeInt) + @as(T, @intFromBool(!isNegative));
        return result * sign;
    }

    pub fn ceilPowerOfTwo(comptime T: type, v: T) T {
        comptime {
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int or ti.int.signedness != .unsigned) @compileError("Expected unsigned integer, but found " + @typeName(T));
        }
        const isPowerOf2: bool = @popCount(v) == 1; // true if v is a power of 2 greater than 0
        const retMax: bool = v > (std.math.maxInt(T) / 2 + 1); // true if the function should return int max for input type
        const shiftBy = @bitSizeOf(T) - @clz(v - @intFromBool(isPowerOf2));
        const r0: T = (@as(T, 1) << @truncate(shiftBy)) * @as(T, @intFromBool(!retMax));
        const r1: T = @as(T, std.math.maxInt(T)) * @as(T, @intFromBool(retMax));
        return r0 + r1;
    }
};
