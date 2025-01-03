const std = @import("std");
const fs = std.fs;
const Path = fs.path;
const File = fs.File;
const Allocator = std.mem.Allocator;

const sorted = @import("sorted/sorted.zig");
const parallel = @import("parallel/parallel.zig");
const ParallelKernel = parallel.ParallelKernel;

const keylen: usize = 100;
const veclen: usize = keylen / @sizeOf(u64);
const MeasurementKey = struct {
    keybuffer: [keylen]u8,
    len: usize,

    pub fn key(self: *MeasurementKey) []u8 {
        return self.keybuffer[0..@min(self.keybuffer.len, self.len)];
    }
    pub fn create(k: []const u8) MeasurementKey {
        // std.debug.print("MeasurementKey.create(\"{s}\")\n", .{k});
        const l: usize = @min(k.len, keylen);
        var r: MeasurementKey = .{ // NOWRAP
            .keybuffer = undefined,
            .len = l,
        };
        std.mem.copyForwards(u8, r.keybuffer[0..l], k[0..l]);
        return r;
    }

    pub fn compare_keys(a: MeasurementKey, b: MeasurementKey) sorted.CompareResult {
        const compare_len_fn = comptime sorted.CompareNumberFn(usize);
        const akey: []u8 = @constCast(&a).key();
        const bkey: []u8 = @constCast(&b).key();
        const comp_len = compare_len_fn(akey.len, bkey.len);
        if (comp_len != .Equal) {
            return comp_len;
        }

        var i: usize = akey.len;
        while (i > 0) {
            i -= 1;
            switch (sorted.CompareNumber(akey[i], bkey[i])) {
                .Equal => {},
                .LessThan => {
                    return .LessThan;
                },
                .GreaterThan => {
                    return .GreaterThan;
                },
            }
        }
        return .Equal;
    }
};
const LineBuffer = [106]u8;
const ParsedLine = struct {
    key: MeasurementKey = undefined,
    value: f64 = -1,

    pub fn init(k: []const u8, v: f64) ParsedLine {
        return ParsedLine{
            .key = MeasurementKey.create(k),
            .value = v,
        };
    }

    pub fn clone(self: *ParsedLine) ParsedLine {
        return self.*;
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
    const MapType = sorted.SortedArrayMap(MeasurementKey, Measurement, MeasurementKey.compare_keys);
    allocator: Allocator,
    lineCount: u32 = 0,
    measurements: MapType,

    pub fn uniqueKeys(self: *const ParsedSet) usize {
        return self.measurements.keys.len;
    }
    pub fn init(allocator: Allocator) ParsedSet {
        return .{ //NOFOLD
            .allocator = allocator,
            .measurements = MapType.init(allocator) catch {
                @panic("failed to init measurements");
            },
        };
    }
    pub fn deinit(self: *ParsedSet) void {
        self.measurements.deinit();
    }

    pub fn AddSync(self: *ParsedSet, parsedLine: *const ParsedLine) !void {
        self.lineCount += 1;
        const idx: isize = self.measurements.indexOf(parsedLine.key);
        if (idx >= 0) {
            // key found, update it
            self.measurements.values[@as(usize, @intCast(idx))].add(parsedLine.value);
        } else {
            // key not found, add it
            self.measurements.update(parsedLine.key, Measurement.init(parsedLine.value));
        }
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
        var buf: [4096]u8 = undefined;
        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line[0] != '#') {
                var pline: ParsedLine = parseLine(line);
                var key: []u8 = pline.key.key();
                _ = &key;
                std.log.debug("line {d}: \"{s}\"\n- key: \"{s}\"\n- val: {d}", .{ parsedSet.lineCount, line, key, pline.value }); // not compiled in ReleaseFast mode
                try parsedSet.AddSync(&pline);
            }
        }
    }
    const Line = struct {
        len: usize,
        buffer: LineBuffer,

        pub fn create(v: []const u8) Line {
            var r = Line{ // NOWRAP
                .buffer = undefined,
                .len = 0,
            };
            std.debug.assert(v.len <= r.buffer.len);
            std.mem.copyForwards(u8, r.buffer[0..v.len], v);
            r.len = v.len;
            // std.log.debug("Line.create: v.len = {d}", .{v.len});
            return r;
        }

        pub fn slice(self: *const Line) []const u8 {
            // std.log.debug("Line.slice: self.len = {d}", .{self.len});
            return self.buffer[0..@min(self.len, self.buffer.len)];
        }

        pub fn parse(v: Line) ParsedLine {
            // std.log.debug("Line.parse(v:\"{s}\")", .{v.buffer});
            const line: []const u8 = v.slice();
            // Splitting on ';'
            var i: usize = 1;
            while (line[i] != ';' and i < line.len) : (i += 1) {}

            const keystr = line[0..i];
            const valstr = line[(i + 1)..];
            const valint: isize = fastIntParse(valstr);
            const val: f64 = @as(f64, @floatFromInt(valint)) / 10.0;
            return ParsedLine.init(keystr, val);
        }
    };
    inline fn readKernel(allocator: Allocator, file: *const File, parsedSet: *ParsedSet) !void {
        var buf: [4096]u8 = undefined;
        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        const kernelSize = 1000;
        var kernel = try ParallelKernel(Line, ParsedLine, Line.parse).init(allocator, kernelSize);
        defer kernel.deinit();
        var line_idx: usize = 0;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line[0] != '#') {
                const L = Line.create(line);
                if (!kernel.writeInput(L)) {
                    try kernel.run();
                    for (0..kernel.count) |i| {
                        var pline: ParsedLine = kernel.results[i];
                        std.log.debug("line {d}: \"{s}\"\n- key: \"{s}\"\n- val: {d}", .{ line_idx, kernel.inputs[i].slice(), pline.key.key(), pline.value });
                        try parsedSet.AddSync(&pline);
                        line_idx += 1;
                    }
                    kernel.resetCount();
                }
            }
        }
        // adding any remaining lines
        try kernel.run();
        for (0..kernel.count) |i| {
            const pline: ParsedLine = kernel.results[i];
            try parsedSet.AddSync(&pline);
        }
    }

    pub fn parse(self: *SetParser, path: []const u8) !ParsedSet {
        var file: File = try FileHelper.openFile(self.allocator, path);
        defer file.close();

        var set: ParsedSet = ParsedSet.init(self.allocator);
        //try readSync(&file, &set);
        try readKernel(self.allocator, &file, &set);
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

    return ParsedLine.init(keystr, val);
}
/// Parses a copy of the line. Safe to use in multithreaded context
fn parseLineCopy(line: LineBuffer) ParsedLine {
    return parseLineBuffer(line);
}
/// Parses decimal number string
pub fn fastIntParse(numstr: []const u8) isize {
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
