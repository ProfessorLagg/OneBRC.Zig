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
        @memcpy(@as(*[vecsize]u8, @ptrCast(&av)), a.buffer[0..vecsize]);
        @memcpy(@as(*[vecsize]u8, @ptrCast(&bv)), b.buffer[0..vecsize]);

        const lt: @Vector(vecsize, i8) = @intFromBool(av < bv) * (comptime @as(@Vector(vecsize, i8), @splat(-1)));
        const gt: @Vector(vecsize, i8) = @intFromBool(av > bv);
        const cmp: [vecsize]i8 = gt + lt;

        inline for (0..vecsize) |i| {
            if (cmp[i] != 0) {
                return @as(sorted.CompareResult, @enumFromInt(cmp[i]));
            }
        }
        return .Equal;
    }

    pub fn compare(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len: usize = @max(a.len, b.len);
        const cmp_vec = compare_vector(a, b);
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

    pub fn wtf8(self: *const MapKey, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= self.len);
        var utf8 = std.unicode.Utf8View.init(self.buffer[0..self.len]) catch |err| {
            std.log.err("err: {s}", .{@errorName(err)});
            @panic(@errorName(err));
        };

        var iterator = utf8.iterator();
        var i: usize = 0;
        while (iterator.nextCodepoint()) |codepoint| {
            const mi = std.unicode.wtf8Encode(codepoint, buf[i..]) catch |err| {
                std.log.err("err: {s}", .{@errorName(err)});
                @panic(@errorName(err));
            };
            i += @as(usize, @intCast(mi));
        }

        return buf[0..i];
    }

    pub fn wtf16le(self: *const MapKey, buf: []u16) []const u8 {
        var wtf8buffer: [bufferlen]u8 = undefined;
        const wtf8slice = self.wtf8(wtf8buffer[0..]);
        const len = std.unicode.wtf8ToWtf16Le(buf, wtf8slice) catch |err| {
            std.log.err("err: {s}", .{@errorName(err)});
            @panic(@errorName(err));
        };
        const result: []const u8 = blk: {
            var r: []const u8 = undefined;
            r.ptr = @ptrCast(&buf[0]);
            r.len = len * (@sizeOf(u16) / @sizeOf(u8));
            break :blk r;
        };
        return result;
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

    pub inline fn unionWith(mv: *MapVal, other: *const MapVal) void {
        mv.count += other.count;
        mv.sum += other.sum;
        mv.min = @min(mv.min, other.min);
        mv.max = @max(mv.max, other.max);
    }

    pub inline fn getMin(self: *MapVal, comptime T: type) T {
        comptime {
            const Ti = @typeInfo(T);
            switch (Ti) {
                .Float => {},
                else => {
                    @compileError("Expected floating point type, but found " ++ @typeName(T));
                },
            }
        }
        const a: T = @floatFromInt(self.min);
        return a / @as(T, 10.0);
    }

    pub inline fn getMax(self: *MapVal, comptime T: type) T {
        comptime {
            const Ti = @typeInfo(T);
            switch (Ti) {
                .Float => {},
                else => {
                    @compileError("Expected floating point type, but found " ++ @typeName(T));
                },
            }
        }
        const a: T = @floatFromInt(self.max);
        return a / @as(T, 10.0);
    }

    pub inline fn getMean(self: *MapVal, comptime T: type) T {
        comptime {
            const Ti = @typeInfo(T);
            switch (Ti) {
                .Float => {},
                else => {
                    @compileError("Expected floating point type, but found " ++ @typeName(T));
                },
            }
        }
        const s: T = @floatFromInt(self.sum);
        const c: T = @floatFromInt(self.count);
        return (s / @as(T, 10.0)) / c;
    }
};

pub const ParseResult = packed struct {
    lineCount: usize = 0,
    uniqueKeys: usize = 0,
};

const readBufferSize: comptime_int = 65_536;

/// For testing purposes only. Reads all the lines in the file, without parsing them.
pub fn read(path: []const u8) !ParseResult {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var file: fs.File = try openFile(allocator, path);
    defer file.close();

    const fileReader = file.reader();
    const TBufferedReader = std.io.BufferedReader(readBufferSize, @TypeOf(fileReader));
    var bufferedReader = TBufferedReader{ .unbuffered_reader = fileReader };
    var reader = bufferedReader.reader();

    var result: ParseResult = .{};
    var buf: [128]u8 = undefined;
    var eof: bool = false;
    fileloop: while (!eof) {
        var splitIndex: usize = 0;
        var bi: usize = 0;
        lineloop: while (bi < buf.len) {
            buf[bi] = reader.readByte() catch |err| {
                switch (err) {
                    error.EndOfStream => {
                        eof = true;
                        break :lineloop;
                    },
                    else => {
                        return err;
                    },
                }
            };

            const isSemi: bool = buf[bi] == ';';
            splitIndex = (bi * @as(usize, @intFromBool(isSemi))) + (splitIndex * @as(usize, @intFromBool(!isSemi)));
            if (buf[bi] == '\n') {
                break :lineloop;
            }
            bi += 1;
        }

        std.log.debug("line: \"{s}\"", .{buf[0..bi]});
        if (buf[0] == '#' or splitIndex < 1) {
            continue :fileloop;
        }
        result.lineCount += 1;
        const keystr: []u8 = buf[0..splitIndex];
        const valstr: []u8 = buf[(splitIndex + 1)..bi];

        _ = &keystr;
        _ = &valstr;
    }

    return result;
}

pub fn parse(path: []const u8, comptime print_result: bool) !ParseResult {
    @setRuntimeSafety(false);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var file: fs.File = try openFile(allocator, path);
    defer file.close();

    const TMap = sorted.SortedArrayMap(MapKey, MapVal, MapKey.compare);

    const mapCount: comptime_int = 64;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.init(allocator);
        }
        break :blk r;
    };

    const fileReader = file.reader();
    const TBufferedReader = std.io.BufferedReader(readBufferSize, @TypeOf(fileReader));
    var bufferedReader = TBufferedReader{ .unbuffered_reader = fileReader };
    var reader = bufferedReader.reader();

    var tKey: MapKey = .{};
    var tVal: MapVal = .{ .count = 1 };
    var result: ParseResult = .{};
    var buf: [128]u8 = undefined;
    var eof: bool = false;
    fileloop: while (!eof) {
        var splitIndex: usize = 0;
        var bi: usize = 0;
        lineloop: while (bi < buf.len) {
            buf[bi] = reader.readByte() catch |err| {
                switch (err) {
                    error.EndOfStream => {
                        eof = true;
                        break :lineloop;
                    },
                    else => {
                        return err;
                    },
                }
            };

            const isSemi: bool = buf[bi] == ';';
            splitIndex = (bi * @as(usize, @intFromBool(isSemi))) + (splitIndex * @as(usize, @intFromBool(!isSemi)));
            if (buf[bi] == '\n') {
                break :lineloop;
            }
            bi += 1;
        }

        if (buf[0] == '#' or splitIndex < 1) {
            continue :fileloop;
        }
        result.lineCount += 1;
        const keystr: []u8 = buf[0..splitIndex];
        const valstr: []u8 = buf[(splitIndex + 1)..bi];
        std.log.debug("line: \"{s}\", keystr: \"{s}\", valstr: \"{s}\"", .{ buf[0..bi], keystr, valstr });
        tKey.set(keystr);

        const mapIndex: usize = (@as(usize, @intCast(tKey.buffer[0])) + tKey.len) % mapCount; // I have tried to beat this but i cant
        const map: *TMap = &maps[mapIndex];

        const valint: u64 = @intCast(fastIntParse(valstr));

        const keyIndex = map.indexOf(&tKey);
        if (keyIndex >= 0) {
            map.values[@as(usize, @intCast(keyIndex))].add(valint);
        } else {
            tVal.max = valint;
            tVal.min = valint;
            tVal.sum = valint;
            _ = map.update(&tKey, &tVal);
        }
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>2}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey: *MapKey = &maps[i].keys[j];
            const rVal: *MapVal = &maps[i].values[j];
            const keyIndex = maps[0].indexOf(rKey);
            if (keyIndex >= 0) {
                maps[0].values[@as(usize, @intCast(keyIndex))].unionWith(rVal);
            } else {
                _ = maps[0].update(rKey, rVal);
            }
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k: *MapKey = &maps[0].keys[i];
            const v: *MapVal = &maps[0].values[i];
            try stdout.print("{s};{d:.1};{d:.1};{d:.1}\n", .{ // NO WRAP
                k.buffer[0..k.len],
                v.getMin(f64),
                v.getMean(f64),
                v.getMax(f64),
            });
        }
    }

    result.uniqueKeys = maps[0].count;
    maps[0].deinit();
    return result;
}
