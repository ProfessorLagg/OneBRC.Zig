// Semi-rewrite for simplifications sake

const std = @import("std");
const fs = std.fs;
const sorted = @import("sorted/sorted.zig");
const compare = sorted.compare;

inline fn fastIntParse(numstr: []const u8) isize {
    // @setRuntimeSafety(false);
    const isNegative: bool = numstr[0] == '-';
    const isNegativeInt: usize = @intFromBool(isNegative);

    var result: isize = 0;
    var m: isize = 1;
    var i: isize = @as(isize, @intCast(numstr.len)) - 1;
    while (i >= isNegativeInt) {
        const ci: isize = @intCast(numstr[@as(usize, @intCast(i))]);
        const valid: bool = ci >= 48 and ci <= 57;
        const validInt: isize = @intFromBool(valid);
        const invalidInt: isize = @intFromBool(!valid);
        const value: isize = validInt * ((ci - 48) * m); // '0' = 48
        result += value;
        m = (m * 10 * validInt) + (m * invalidInt);
        i -= 1;
    }
    return result;
}

fn toAbsolutePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const cwd_path = try fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);
    return try fs.path.resolve(allocator, &.{
        cwd_path,
        path,
    });
}

fn openFile(allocator: std.mem.Allocator, path: []const u8) !fs.File {
    const absPath: []u8 = try toAbsolutePath(allocator, path);
    defer allocator.free(absPath);
    return try fs.openFileAbsolute(absPath, comptime fs.File.OpenFlags{ //NOFOLD
        .mode = .read_only,
        .lock = .shared,
        .lock_nonblocking = false,
        .allow_ctty = false,
    });
}

pub const MapKey = struct {
    const bufferlen: usize = 100;
    const vecsize = 32;
    len: usize = 0,
    buffer: [bufferlen]u8 align(vecsize) = undefined,

    pub fn create(str: []const u8) MapKey {
        std.debug.assert(str.len <= bufferlen);
        var r = MapKey{ .buffer = undefined, .len = str.len };
        @memcpy(r.buffer[0..str.len], str);
        return r;
    }

    pub inline fn set(self: *MapKey, str: []const u8) void {
        std.debug.assert(str.len <= bufferlen);
        @memset(self.buffer[0..], 0);
        @memcpy(self.buffer[0..str.len], str);
        self.len = str.len;
    }

    inline fn compare_vector(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        @setRuntimeSafety(false);

        var av: @Vector(32, u8) = undefined;
        var bv: @Vector(32, u8) = undefined;

        // TODO it should be possible to get rid of these memcpy
        @memcpy(@as(*[32]u8, @ptrCast(&av)), a.buffer[0..32]);
        @memcpy(@as(*[32]u8, @ptrCast(&bv)), b.buffer[0..32]);

        const lt: @Vector(32, i8) = @intFromBool(av < bv) * (comptime @as(@Vector(32, i8), @splat(-1)));
        const gt: @Vector(32, i8) = @intFromBool(av > bv);
        const cmp: [32]i8 = gt + lt;

        inline for (0..32) |i| {
            if (cmp[i] != 0) {
                return @as(sorted.CompareResult, @enumFromInt(cmp[i]));
            }
        }
        return .Equal;
    }
    pub fn compare_v4(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        const cmp_vec = compare_vector(a, b);
        if (len <= 32 or cmp_vec != .Equal) {
            return cmp_vec;
        }

        inline for (32..a.buffer.len) |i| {
            const lt: i8 = @intFromBool(a.buffer[i] < b.buffer[i]) * @as(i8, -1); // -1 if true, 0 if false
            const gt: i8 = @intFromBool(a.buffer[i] > b.buffer[i]); // 1 if true, 0 if false
            const char_compare = @as(sorted.CompareResult, @enumFromInt(lt + gt));
            if (char_compare != .Equal) {
                return char_compare;
            }
        }
        return .Equal;
    }

    inline fn compare_vector3(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        @setRuntimeSafety(false);

        const av: *const @Vector(vecsize, u8) = @ptrFromInt(@intFromPtr(&a.buffer[0]));
        const bv: *const @Vector(vecsize, u8) = @ptrFromInt(@intFromPtr(&b.buffer[0]));

        const cmp: [vecsize]i8 =
            ((@intFromBool(av.* < bv.*) * (comptime @as(@Vector(vecsize, i8), @splat(-1)))) // Less Than
        + (@intFromBool(av.* > bv.*))); // Greater than

        const di = std.simd.firstTrue(@as(@Vector(vecsize, i8), cmp) != (comptime @as(@Vector(vecsize, i8), @splat(0)))) orelse return .Equal;

        return @as(sorted.CompareResult, @enumFromInt(cmp[@as(usize, @intCast(di))]));
    }
    pub fn compare_v5(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        const cmp_vec = compare_vector3(a, b);
        if (len <= vecsize or cmp_vec != .Equal) {
            return cmp_vec;
        }

        inline for (vecsize..a.buffer.len) |i| {
            const lt: i8 = @intFromBool(a.buffer[i] < b.buffer[i]) * @as(i8, -1); // -1 if true, 0 if false
            const gt: i8 = @intFromBool(a.buffer[i] > b.buffer[i]); // 1 if true, 0 if false
            const char_compare = @as(sorted.CompareResult, @enumFromInt(lt + gt));
            if (char_compare != .Equal) {
                return char_compare;
            }
        }
        return .Equal;
    }

    pub fn compare(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        return compare_v4(a, b);
    }
};

const MapVal = packed struct {
    count: u64 = 0,
    sum: u64 = 0,
    min: u64 = std.math.maxInt(u64),
    max: u64 = std.math.minInt(u64),

    pub inline fn add(mv: *MapVal, v: u64) void {
        mv.count += 1;
        mv.sum += v;
        mv.min = @min(mv.min, v);
        mv.max = @max(mv.max, v);
    }
};

pub const ParseResult = struct {
    lineCount: usize = 0,
    uniqueKeys: usize = 0,
};
pub fn parse(path: []const u8) !ParseResult {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var file: fs.File = try openFile(allocator, path);
    defer file.close();

    var map: sorted.SortedArrayMap(MapKey, MapVal, MapKey.compare) = try sorted.SortedArrayMap(MapKey, MapVal, MapKey.compare).init(allocator);
    defer map.deinit();

    var buf: [128]u8 = undefined;
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var tKey: MapKey = .{};
    var tVal: MapVal = .{ .count = 1 };
    var result: ParseResult = .{};
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line[0] == '#') {
            continue;
        }

        result.lineCount += 1;
        var splitIndex: usize = 1;
        while (line[splitIndex] != ';' and splitIndex < line.len) : (splitIndex += 1) {}

        const key: []u8 = line[0..splitIndex];
        tKey.set(key);

        const valint: u64 = @intCast(fastIntParse(line[splitIndex + 1 ..]));

        const mapIndex = map.indexOf(&tKey);
        if (mapIndex >= 0) {
            map.values[@as(usize, @intCast(mapIndex))].add(valint);
        } else {
            tVal.max = valint;
            tVal.min = valint;
            tVal.sum = valint;
            _ = map.update(&tKey, &tVal);
        }
    }

    result.uniqueKeys = map.count;
    return result;
}
