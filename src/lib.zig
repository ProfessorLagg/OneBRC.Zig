const std = @import("std");
const fs = std.fs;
const Path = fs.path;
const File = fs.File;
const Allocator = std.mem.Allocator;
const xxhash = @import("xxhash.zig").xxhash;

const sorted = @import("sorted/sorted.zig");
const Comparison = sorted.Comparison;

const keylen: usize = 104;
const veclen: usize = keylen / @sizeOf(u64);
const MeasurementKey = struct {
    keybuffer: [keylen]u8,
    key: []u8,

    pub fn create(k: []const u8) MeasurementKey {
        var r: MeasurementKey = .{ // NOWRAP
            .keybuffer = undefined,
            .key = undefined,
        };
        const l: usize = @min(keylen, k.len);
        const tempk = k[0..l];
        r.key = r.keybuffer[0..l];
        std.mem.copyForwards(u8, r.key, tempk);
        return r;
    }
};
const LineBuffer = [105]u8;
const ParsedLine = struct {
    key: MeasurementKey = undefined,
    value: f64 = -1,

    pub fn init(k: []const u8, v: f64) ParsedLine {
        return ParsedLine{
            .key = MeasurementKey.create(k),
            .value = v,
        };
    }
};
const MeasurementContext64 = struct {
    pub fn hash(ctx: MeasurementContext64, key: MeasurementKey) u64 {
        @setRuntimeSafety(false);
        _ = &ctx;
        return xxhash.checksum(key.key, 0x2025_01_03);
    }
    pub fn eql(ctx: MeasurementContext64, a: MeasurementKey, b: MeasurementKey) bool {
        @setRuntimeSafety(false);
        _ = &ctx;
        if (a.key.len != b.key.len) {
            return false;
        }
        const l: usize = a.key.len;
        for (0..l) |i| {
            if (a.key[i] != b.key[i]) {
                return false;
            }
        }
        return true;
        // return std.mem.eql(u8, a.key, b.key);
    }
};
const MeasurementContext32 = struct {
    fn combine(uint64: u64) u32 {
        const vec: @Vector(2, u32) = @as(*@Vector(2, u32), @ptrFromInt(@intFromPtr(&uint64))).*;
        return vec[0] ^ vec[1];
    }
    pub fn hash(ctx: MeasurementContext32, key: MeasurementKey) u32 {
        @setRuntimeSafety(false);
        _ = &ctx;
        const v: u64 = xxhash.checksum(key.key, 0x2025_01_03);
        return combine(v);
    }
    pub fn eql(ctx: MeasurementContext32, a: MeasurementKey, b: MeasurementKey) bool {
        @setRuntimeSafety(false);
        _ = &ctx;
        return std.mem.eql(u8, a[0..], b[0..]);
    }
};
const Measurement = struct {
    count: u64 = 0,
    sum: f64 = 0.0,
    min: f64 = std.math.floatMax(f64),
    max: f64 = std.math.floatMin(f64),
    pub inline fn init(v: f64) Measurement {
        return Measurement{ .count = 1, .sum = v, .min = v, .max = v };
    }
    pub inline fn mean(self: *const Measurement) f64 {
        return self.sum / @as(f64, @floatFromInt(self.count));
    }
    pub inline fn add(self: *Measurement, v: f64) void {
        self.count += 1;
        self.sum += v;
        self.min = @min(self.min, v);
        self.max = @min(self.max, v);
    }
};
pub const ParsedSet = struct {
    //const MapType = std.AutoArrayHashMap(MeasurementKey, Measurement);
    //const MapType = std.AutoHashMap(MeasurementKey, Measurement);
    const MapType = std.HashMap(MeasurementKey, Measurement, MeasurementContext64, 80);
    //const MapType = std.ArrayHashMap(MeasurementKey, Measurement, MeasurementContext32, false);
    // const MapType = std.ArrayHashMap(MeasurementKey, Measurement, MeasurementContext32, false);
    allocator: Allocator,
    lineCount: u32 = 0,
    measurements: MapType,
    uniqueKeys: u32 = 0,

    pub fn init(allocator: Allocator) ParsedSet {
        return .{ //NOFOLD
            .allocator = allocator,
            .measurements = MapType.init(allocator),
        };
    }
    pub fn deinit(self: *ParsedSet) void {
        self.measurements.deinit();
    }

    pub fn AddSync(self: *ParsedSet, parsedLine: *const ParsedLine) !void {
        var ptr: ?*Measurement = self.measurements.getPtr(parsedLine.key);
        if (!self.measurements.contains(parsedLine.key)) {
            try self.measurements.put(parsedLine.key, Measurement.init(parsedLine.value));
        } else {
            ptr.?.add(parsedLine.value);
            self.uniqueKeys += 1;
        }
        self.lineCount += 1;
    }

    // TODO Multithreading safe Add function
};
pub const SetParser = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) SetParser {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SetParser) void {
        _ = &self;
    }

    inline fn readSync(file: *const File, parsedSet: *ParsedSet) !void {
        var buf: LineBuffer = undefined;
        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line[0] != '#') {
                std.log.debug("line {d}: \"{s}\"\n", .{ parsedSet.lineCount, line }); // not compiled in ReleaseFast mode
                const pline: ParsedLine = parseLine(line);
                try parsedSet.AddSync(&pline);
            }
        }
    }
    pub fn parse(self: *SetParser, path: []const u8) !ParsedSet {
        var file: File = try FileHelper.openFile(self.allocator, path);
        defer file.close();

        var set: ParsedSet = ParsedSet.init(self.allocator);
        try readSync(&file, &set);
        return set;
    }
};

fn parseLine(line: []u8) ParsedLine {
    // Splitting on ';'
    var i: usize = 1;
    while (line[i] != ';' and i < line.len) : (i += 1) {}

    const keystr = line[0..i];
    const valstr = line[(i + 1)..];
    const valint: isize = fastIntParse(valstr);
    const val: f64 = @as(f64, @floatFromInt(valint)) / 10.0;

    std.log.debug("valstr: |{s}|", .{valstr});

    return ParsedLine.init(keystr, val);
}
fn parseLineBuffer(line: *LineBuffer) ParsedLine {
    const l: usize = @min(keylen, line.len);
    // Splitting on ';'
    var idx_semicolon: usize = 1;
    var idx_newline: usize = 5;
    for (0..l) |i| {
        const is_semicolon: bool = line[i] == ';';
        idx_semicolon = (i * @as(usize, @intFromBool(is_semicolon))) + (idx_semicolon * @as(usize, @intFromBool(!is_semicolon)));

        const is_newline: bool = line[i] == '\n';
        idx_newline = (i * @as(usize, @intFromBool(is_newline))) + (idx_newline * @as(usize, @intFromBool(!is_newline)));
        if (is_newline) {
            break;
        }
    }

    const keystr = line[0..idx_semicolon];
    const valstr = line[idx_semicolon + 1 .. idx_newline];
    const valint: isize = fastIntParse(valstr);
    const val: f64 = @as(f64, @floatFromInt(valint)) / 10.0;

    std.log.debug("valstr: |{s}|", .{valstr});

    return ParsedLine.init(keystr, val);
}
/// Parses a copy of the line. Safe to use in multithreaded context
fn parseLineCopy(line: LineBuffer) ParsedLine {
    return parseLineBuffer(line);
}
/// Parses decimal number string
pub fn fastIntParse(numstr: []u8) isize {
    // @setRuntimeSafety(false);
    const isNegative: bool = numstr[0] == '-';
    const isNegativeInt: usize = @intFromBool(isNegative);

    var result: isize = 0;
    var m: isize = 1;
    var i: isize = @as(isize, @intCast(numstr.len)) - 1;
    std.log.debug("fastIntParse(numstr: \"{s}\")\n\tisNegativeInt: {d}", .{ numstr, isNegativeInt });
    while (i >= isNegativeInt) {
        std.log.debug("fastIntParse i: {d}", .{i});
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

const FileHelper = struct {
    fn openFile(allocator: Allocator, path: []const u8) !File {
        const absPath: []u8 = try toAbsolutePath(allocator, path);
        defer allocator.free(absPath);

        return try fs.openFileAbsolute(absPath, comptime File.OpenFlags{ //NOFOLD
            .mode = .read_only,
            .lock = .shared,
            .lock_nonblocking = false,
            .allow_ctty = false,
        });
    }

    fn toAbsolutePath(allocator: Allocator, path: []const u8) ![]u8 {
        const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd_path);
        return try std.fs.path.resolve(allocator, &.{
            cwd_path,
            path,
        });
    }
};
