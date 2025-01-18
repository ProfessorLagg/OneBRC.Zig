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
    len: usize = 0,
    buffer: [bufferlen]u8 = undefined,

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

    inline fn cmpsb(len: usize, a: *const u8, b: *const u8) sorted.CompareResult {
        const eflags = asm volatile ( // NO FOLD
            "repe cmpsb\n" ++ "PUSHFQ\n" ++ "POP %%rax"
            : [ret] "={rax}" (-> u64),
            : [a] "{rdi}" (a),
              [b] "{rsi}" (b),
              [l] "{rcx}" (len),
        );

        if (eflags == 0x246) {
            return .Equal;
        }
        const masked_eflags: u64 = eflags & @as(u64, 0x203);
        const result: sorted.CompareResult = switch (masked_eflags) {
            @as(u64, 0x203) => .LessThan,
            @as(u64, 0x202) => .GreaterThan,
            else => unreachable,
        };
        return result;
    }

    pub fn compare_v1(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        for (0..len) |i| {
            const lt: i8 = @intFromBool(a.buffer[i] < b.buffer[i]) * @as(i8, -1); // -1 if true, 0 if false
            const gt: i8 = @intFromBool(a.buffer[i] > b.buffer[i]); // 1 if true, 0 if false
            const char_compare = @as(sorted.CompareResult, @enumFromInt(lt + gt));
            if (char_compare != .Equal) {
                return char_compare;
            }
        }
        return .Equal;
    }
    pub fn compare_v2(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        // v2
        const len: usize = @max(a.len, b.len);
        for (0..len) |i| {
            const char_compare = sorted.compareFromBools(a.buffer[i] < b.buffer[i], a.buffer[i] > b.buffer[i]);
            if (char_compare != .Equal) {
                return char_compare;
            }
        }
        return .Equal;
    }

    inline fn compare_vector(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        var av: [32]i8 = undefined;
        var bv: [32]i8 = undefined;
        @memcpy(&av, @as([]const i8, @ptrCast(a.buffer[0..32])));
        @memcpy(&bv, @as([]const i8, @ptrCast(b.buffer[0..32])));
        const dv: [32]i8 = std.math.sign(@as(@Vector(32, i8), av) - @as(@Vector(32, i8), bv));
        inline for (0..32) |i| {
            switch (dv[i]) {
                -1 => return .LessThan,
                1 => return .GreaterThan,
                0 => {},
                else => unreachable,
            }
        }
        return .Equal;
    }
    pub fn compare_v3(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        if (len <= 32) {
            return compare_vector(a, b);
        }

        for (0..len) |i| {
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
        return compare_v2(a, b);
    }

    pub fn compare_asm(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        return cmpsb(len, &a.buffer[0], &b.buffer[0]);
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
