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

const MapKey = struct {
    const bufferlen: usize = 100;
    buffer: [bufferlen]u8 = undefined,
    len: usize = 0,

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

    fn cmp_asm(len: usize, a: *const u8, b: *const u8) sorted.CompareResult {
        return asm volatile(
            "mov $0xff, %%bx\n" ++ "mov $0, %%cx\n" ++ "mov $0x10, %%dx\n" ++ "repe cmpsb\n" ++ "cmova %%ax, %%bx\n" ++ "cmove %%ax, %%cx\n" ++ "cmovb %%ax, %%dx"
            : [ret] "={ah}" (-> sorted.CompareResult)
            :[a] "{rdi}" (a),
            [b] "{rsi}" (b),
            [l] "{rcx}" (len),
            : "ax", "bx", "cx", "dx"
        );
    }

    pub fn compare(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        // const cmp_len = sorted.compareFromBools(a.len < b.len, a.len > b.len);
        // if (cmp_len != .Equal) {
        //     return cmp_len;
        // }
        const len: usize = @max(a.len, b.len);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (a.buffer[i] < b.buffer[i]) {
                return .LessThan;
            } else if (a.buffer[i] > b.buffer[i]) {
                return .GreaterThan;
            }
        }
        return .Equal;
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
