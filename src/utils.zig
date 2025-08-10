const builtin = @import("builtin");
const std = @import("std");
const _asm = @import("_asm.zig");

pub const mem = struct {
    pub const staticAllocator: std.mem.Allocator = b: {
        if (builtin.is_test) break :b std.testing.allocator;
        if (!builtin.single_threaded) break :b std.heap.smp_allocator;
        if (builtin.link_libc) break :b std.heap.c_allocator;
        @compileError("Requires either single-threading to be disabled or lib-c to be linked");
    };

    pub const KiloByte: comptime_int = 1024;
    pub const MegaByte: comptime_int = KiloByte * 1024;
    pub const GigaByte: comptime_int = MegaByte * 1024;
    pub const TeraByte: comptime_int = GigaByte * 1024;

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

    pub fn eqlBytes(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (0..a.len) |i| if (a[i] != b[i]) return false;
        return true;
    }

    pub fn clone(comptime T: type, allocator: std.mem.Allocator, arr: []const T) ![]T {
        const out: []T = try allocator.alloc(T, arr.len);
        @memcpy(out, arr);
        return out;
    }

    /// Reads `v` as an array of bytes and encodes it as an uppercase hex string
    pub fn toBinaryHexString(comptime T: type, v: T) [@sizeOf(T) * 2]u8 {
        const hex_strings = [256]*const [2:0]u8{ "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "0A", "0B", "0C", "0D", "0E", "0F", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "1A", "1B", "1C", "1D", "1E", "1F", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "2A", "2B", "2C", "2D", "2E", "2F", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "3A", "3B", "3C", "3D", "3E", "3F", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "4A", "4B", "4C", "4D", "4E", "4F", "50", "51", "52", "53", "54", "55", "56", "57", "58", "59", "5A", "5B", "5C", "5D", "5E", "5F", "60", "61", "62", "63", "64", "65", "66", "67", "68", "69", "6A", "6B", "6C", "6D", "6E", "6F", "70", "71", "72", "73", "74", "75", "76", "77", "78", "79", "7A", "7B", "7C", "7D", "7E", "7F", "80", "81", "82", "83", "84", "85", "86", "87", "88", "89", "8A", "8B", "8C", "8D", "8E", "8F", "90", "91", "92", "93", "94", "95", "96", "97", "98", "99", "9A", "9B", "9C", "9D", "9E", "9F", "A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "AA", "AB", "AC", "AD", "AE", "AF", "B0", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "BA", "BB", "BC", "BD", "BE", "BF", "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "CA", "CB", "CC", "CD", "CE", "CF", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "DA", "DB", "DC", "DD", "DE", "DF", "E0", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "EA", "EB", "EC", "ED", "EE", "EF", "F0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "FA", "FB", "FC", "FD", "FE", "FF" };
        var result: [@sizeOf(T) * 2]u8 = undefined;

        const bytes: [@sizeOf(T)]u8 = @bitCast(v);
        inline for (bytes, 0..bytes.len) |byte, i| {
            const hexstr = hex_strings[byte];
            result[i * 2] = hexstr[0];
            result[(i * 2) + 1] = hexstr[1];
        }
        return result;
    }

    inline fn compare_from_bools(lessThan: bool, greaterThan: bool) i8 {
        std.debug.assert((lessThan and greaterThan) != true);
        // case gt = 0, lt = 1 => 0 - 1 == -1
        // case gt = 1, lt = 0 => 1 - 0 == 1
        // case gt = 0, lt = 0 => 0 - 0 == 0
        return @as(i8, @intFromBool(greaterThan)) - @as(i8, @intFromBool(lessThan));
    }
    inline fn compare_string(a: []const u8, b: []const u8) i8 {
        const l: usize = @min(a.len, b.len);
        var i: usize = 0;
        var c: i8 = 0;
        while (i < l and c == 0) : (i += 1) c = compare_from_bools(a[i] < b[i], a[i] > b[i]);
        if (c != 0) return c;
        return compare_from_bools(a.len < b.len, a.len > b.len);
    }
};

pub const math = struct {
    pub fn divCeil(x: isize, y: isize) isize {
        const xf: f64 = @floatFromInt(x);
        const yf: f64 = @floatFromInt(y);
        const rf: f64 = @ceil(xf / yf);
        return @intFromFloat(rf);
    }

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
        while (i >= isNegativeInt) {
            const ci: T = @intCast(numstr[@as(usize, @bitCast(i))]);
            const valid: bool = ci >= 48 and ci <= 57;
            const validInt: T = @intFromBool(valid);
            const invalidInt: T = @intFromBool(!valid);
            result += validInt * ((ci - 48) * m); // '0' = 48
            m = (m * 10 * validInt) + (m * invalidInt);
            i -= 1;
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

    pub fn sumBytes(bytes: []const u8) usize {
        @setRuntimeSafety(false);
        // TODO Vectorize this
        var sum: usize = 0;
        for (bytes) |byte| sum += byte;
        return sum;
    }

    /// returns `x^y`. `T` must be an unsigned integer type.
    /// Result can overflow without warning or assertion
    pub fn powUInt(comptime T: type, x: T, y: T) T {
        comptime {
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int) @compileError("Expected unsigned integer, but found " ++ @typeName(T));
            if (ti.int.signedness != .signed) @compileError("Expected unsigned integer, but found " ++ @typeName(T));
        }
        @setRuntimeSafety(false);
        var r: T = 1;
        for (0..y) |_| r *%= x;
        return r;
    }

    /// rounds x to the next multiple of y away from 0.
    /// only works on unsigned integers
    pub fn nextMultipleOf(comptime T: type, x: T, y: T) T {
        comptime {
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int) @compileError("Expected unsigned integer, but found " ++ @typeName(T));
            if (ti.int.signedness != .signed) @compileError("Expected unsigned integer, but found " ++ @typeName(T));
        }

        const d: T = x / y;
        return (d + @intFromBool((x * d) == y)) * y;
    }
};

pub const hashing = struct {
    pub fn UntilDelimResult(comptime T: type) type {
        return struct {
            hash: T = undefined,
            delim_index: ?usize = null,
        };
    }
    pub fn fnv1a32(data: []const u8) u32 {
        @setRuntimeSafety(false);
        const fnv_prime: comptime_int = 16777619;
        var hash: u32 = 2166136261;
        for (data) |byte| {
            hash ^= @as(u32, @intCast(byte));
            hash *%= fnv_prime;
        }
        return hash;
    }
    /// Calculates FNV-1a 32-bit hash of `line` until `delim` is reached. `delim` is not included in the hash.
    /// Returns both the hash value and index of `delim`.
    pub fn fnv1a32UntilDelim(comptime delim: u8, line: []const u8) UntilDelimResult(u32) {
        @setRuntimeSafety(false);
        const fnv_prime: comptime_int = 16777619;
        const fnv_offset_basis: comptime_int = 0x811c9dc5;
        var result: UntilDelimResult(u32) = .{
            .hash = fnv_offset_basis,
            .delim_index = null,
        };
        for (line, 0..line.len) |byte, i| {
            if (byte == delim) {
                result.delim_index = i;
                break;
            }
            result.hash ^= @as(u32, @intCast(byte));
            result.hash *%= fnv_prime;
        }
        return result;
    }

    pub fn fnv1a64(data: []const u8) u64 {
        @setRuntimeSafety(false);
        const fnv_prime: comptime_int = 1099511628211;
        var hash: u64 = 0xcbf29ce484222325;
        for (data) |byte| {
            hash ^= @as(u64, @intCast(byte));
            hash *%= fnv_prime;
        }
        return hash;
    }
    /// Calculates FNV-1a 64-bit hash of `line` until `delim` is reached. `delim` is not included in the hash.
    /// Returns both the hash value and index of `delim`.
    pub fn fnv1a64UntilDelim(comptime delim: u8, line: []const u8) UntilDelimResult(u64) {
        @setRuntimeSafety(false);
        const fnv_prime: comptime_int = 1099511628211;
        const fnv_offset_basis: comptime_int = 0xcbf29ce484222325;
        var result: UntilDelimResult(u64) = .{
            .hash = fnv_offset_basis,
            .delim_index = null,
        };
        for (line, 0..line.len) |byte, i| {
            if (byte == delim) {
                result.delim_index = i;
                break;
            }
            result.hash ^= @as(u32, @intCast(byte));
            result.hash *%= fnv_prime;
        }
        return result;
    }
};

pub const meta = struct {
    /// Returns a slice of `T` with 0 length and ptr set to `@ptrFromInt(@alignOf(T))`
    pub fn zeroedSlice(comptime T: type) []T {
        var r: []T = undefined;
        r.len = 0;
        r.ptr = @ptrFromInt(@alignOf(T));
        return r;
    }
};

pub const fs = struct {
    pub fn getFilePath(file: std.fs.File, out_buffer: *[std.fs.max_path_bytes]u8) ![]const u8 {
        return try std.os.getFdPath(file.handle, out_buffer);
    }
};

const _debug = struct {
    const BufferedWriter: type = std.io.BufferedWriter(std.math.maxInt(u16), std.fs.File.Writer);
    var print_buf_writer: ?BufferedWriter = null;
    var print_writer: ?BufferedWriter.Writer = null;
    var print_lock: std.Thread.Mutex = .{};

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        std.debug.assert(!@inComptime());
        print_lock.lock();
        defer print_lock.unlock();

        if (print_writer == null) {
            print_buf_writer = .{ .unbuffered_writer = std.io.getStdErr().writer() };
            print_writer = print_buf_writer.?.writer();
        }
        std.fmt.format(print_writer.?, fmt, args) catch |e| std.debug.panic("\nformat(\"{s}\", {any}) failed: {any}{any}", .{ fmt, args, e, @errorReturnTrace() });
    }
    pub fn printLn(comptime fmt: []const u8, args: anytype) void {
        print(fmt ++ "\n", args);
    }
    pub fn flush() void {
        if (print_buf_writer == null) return;
        print_lock.lock();
        defer print_lock.unlock();
        print_buf_writer.?.flush() catch |e| std.debug.panic("\n_print_buf_writer.?.flush() failed: {any}{any}", .{ e, @errorReturnTrace() });
    }
    pub fn assertPanic(ok: bool, comptime fmt: []const u8, args: anytype) void {
        if (!ok) {
            @branchHint(.cold);
            std.debug.panic(fmt, args);
        }
    }
};
const _debug_nop = struct {
    // TODO Dynamically construct from @typeInfo(_debug);
    pub fn print(comptime _: []const u8, _: anytype) void {}
    pub fn printLn(comptime _: []const u8, _: anytype) void {}
    pub fn flush() void {}
    pub fn assertPanic(_: bool, comptime _: []const u8, _: anytype) void {}
};
pub const debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => _debug,
    else => _debug_nop,
};

test hashing {
    _ = hashing;
}
