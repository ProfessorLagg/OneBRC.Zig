// Semi-rewrite for simplifications sake
const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const sorted = @import("sorted/sorted.zig");
const compare = sorted.compare;

/// Type of int used in the MapVal struct
const Tuv = u32;
/// Type of map used in parse function
const TMap = sorted.SortedArrayMap(MapKey, MapVal, MapKey.compare);

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

inline fn divCiel(comptime T: type, numerator: T, denominator: T) T {
    return 1 + ((numerator - 1) / denominator);
}

fn rotateBuffer(buffer: []u8, pos: usize) usize {
    const rembytes: []const u8 = buffer[pos..];
    const remlen: usize = rembytes.len;
    std.log.debug("\n===== pre rembytes =====\n({s})[{s}]\n", .{ buffer[0..remlen], buffer[remlen..] });
    std.mem.copyForwards(u8, buffer, rembytes);
    std.log.debug("\n===== post rembytes =====\n({s})[{s}]\n", .{ buffer[0..remlen], buffer[remlen..] });
    return remlen;
}

pub const MapKey = struct {
    const bufferlen: usize = 100;
    /// contains the (index + 1) * -1 for every position in the vector. ie: {-1, -2, -3}
    const invidx: @Vector(bufferlen, i8) = blk: {
        if (!@inComptime()) {
            std.log.err("NOT IN COMPTIME!");
            unreachable;
        }
        var r: @Vector(bufferlen, i8) = std.simd.iota(i8, bufferlen);
        r += @as(@Vector(bufferlen, i8), @splat(1));
        r *= @as(@Vector(bufferlen, i8), @splat(-1));
        break :blk r;
    };

    buffer: [bufferlen]u8 = undefined,
    len: u8 = 0,

    pub inline fn create(str: []const u8) MapKey {
        var r: MapKey = .{};
        r.set(str);
        return r;
    }

    pub inline fn set(self: *MapKey, str: []const u8) void {
        std.debug.assert(str.len <= bufferlen);
        self.len = @as(u8, @intCast(str.len));
        std.mem.copyForwards(u8, &self.buffer, str);
    }

    /// Returns the key as a string
    pub inline fn get(self: *const MapKey) []const u8 {
        return self.buffer[0..self.len];
    }

    pub inline fn compare_valid(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const len = @max(a.len, b.len);
        for (0..len) |i| {
            const cmp_char = sorted.compareNumber(a.buffer[i], b.buffer[i]);
            if (cmp_char != .Equal) {
                return cmp_char;
            }
        }
        return .Equal;
    }

    pub fn compare(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        const type_cmp: type = u32;
        const size_cmp: comptime_int = @sizeOf(type_cmp);
        std.debug.assert(bufferlen % size_cmp == 0);

        var cmp: i8 = @intFromBool(a.len < b.len) * @as(i8, -1);
        cmp += @intFromBool(a.len > b.len);

        const len32: usize = divCiel(u8, @max(a.len, b.len), size_cmp);
        var a32: []align(1) const type_cmp = undefined;
        a32.ptr = @ptrCast(&a.buffer[0]);
        a32.len = len32;
        var b32: []align(1) const type_cmp = undefined;
        b32.ptr = @ptrCast(&b.buffer[0]);
        b32.len = len32;

        var i: usize = 0;
        while (cmp == 0 and i < len32) : (i += 1) {
            cmp = @intFromBool(a32[i] < b32[i]);
            cmp *= -1;
            cmp += @intFromBool(a32[i] > b32[i]);
        }
        return @enumFromInt(cmp);
    }

    /// simd optimized equality check between MapKey data
    pub inline fn equal(a: *const MapKey, b: *const MapKey) bool {
        // TODO only compare the part that has actual data.
        // TODO chunk into 16 byte, 32 byte, 64 byte or 100 byte vectors based on the longest input key
        const aVecptr: *align(1) const @Vector(bufferlen, u8) = @ptrCast(&a.buffer[0]);
        const bVecptr: *align(1) const @Vector(bufferlen, u8) = @ptrCast(&b.buffer[0]);
        return @reduce(.And, aVecptr.* == bVecptr.*);
    }

    /// finds the index of the last difference between the keys. if no difference found, returns 0
    pub inline fn maxDifferenceIndex(a: *const MapKey, b: *const MapKey) u8 {
        const vlen: comptime_int = bufferlen;
        const aVecptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&a.buffer[0]);
        const bVecptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&b.buffer[0]);
        const vec: @Vector(vlen, u8) = @as(@Vector(vlen, u8), @intFromBool(aVecptr.* != bVecptr.*)) * (comptime std.simd.iota(u8, vlen));
        return @reduce(.Max, vec);
    }

    inline fn compare_vector(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
        @setRuntimeSafety(false);

        const av_ptr: *align(1) const @Vector(32, u8) = @ptrCast(&a.buffer[0]);
        const bv_ptr: *align(1) const @Vector(32, u8) = @ptrCast(&b.buffer[0]);

        const lt: @Vector(32, i8) = @intFromBool(av_ptr.* < bv_ptr.*) * (comptime @as(@Vector(32, i8), @splat(-1)));
        const gt: @Vector(32, i8) = @intFromBool(av_ptr.* > bv_ptr.*);
        const cmp: [32]i8 = gt + lt;

        inline for (0..32) |i| {
            if (cmp[i] != 0) {
                return @as(sorted.CompareResult, @enumFromInt(cmp[i]));
            }
        }
        return .Equal;
    }

    pub fn compare2(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
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
};

const MapVal = struct {
    count: Tuv = 0,
    sum: Tuv = 0,
    min: Tuv = std.math.maxInt(Tuv),
    max: Tuv = std.math.minInt(Tuv),

    pub inline fn addRaw(mv: *MapVal, v: Tuv) void {
        mv.count += 1;
        mv.sum += v;
        mv.min = @min(mv.min, v);
        mv.max = @max(mv.max, v);
    }

    pub fn add(mv: *MapVal, other: *const MapVal) void {
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

pub const ParseResult = struct {
    lineCount: usize = 0,
    uniqueKeys: usize = 0,
};

const readBufferSize: comptime_int = 1024 * 1024; // 1mb

const DelimReaderLog = std.log.scoped(.DelimReader);
/// Iterator to read a file line by line
fn DelimReader(comptime Treader: type, comptime delim: u8, comptime buffersize: usize) type {
    comptime {
        if (!std.meta.hasMethod(Treader, "read")) {
            @compileError("Treader type " ++ @typeName(Treader) ++ " does not have a .read method");
        }
    }

    return struct {
        const TSelf = @This();
        allocator: std.mem.Allocator,
        reader: Treader,
        buffer: []u8,
        slice: []u8,

        pub fn init(allocator: std.mem.Allocator, reader: Treader) !TSelf {
            std.log.debug("DelimReader" ++
                "\n\t" ++ "Treader: " ++ "{s}" ++
                "\n\t" ++ "delim: {d} | 0x{X:0>2}" ++
                "\n\t" ++ "buffer size: {d}" ++ "\n", .{ @typeName(Treader), delim, delim, buffersize });
            var r = TSelf{ // NO FOLD
                .allocator = allocator,
                .buffer = try allocator.alloc(u8, buffersize),
                .reader = reader,
                .slice = undefined,
            };
            r.slice = r.buffer[0..];
            r.slice.len = r.reader.read(r.buffer) catch |err| {
                allocator.free(r.buffer);
                return err;
            };
            return r;
        }

        pub fn deinit(self: *TSelf) void {
            self.allocator.free(self.buffer);
        }

        /// Finds index of self.slice[0] in self.buffer
        inline fn getpos(self: *TSelf) usize {
            return @intFromPtr(self.slice.ptr) - @intFromPtr(&self.buffer[0]);
        }

        /// returns the index in self.slice of the next delimiter, otherwise null
        inline fn nextDelimIndex(self: *TSelf) ?usize {
            for (0..self.slice.len) |i| {
                if (self.slice[i] == delim) {
                    return i;
                }
            }
            return null;
        }

        pub inline fn next(self: *TSelf) !?[]const u8 {
            goto: while (true) {
                if (self.slice.len == 0) {
                    // contains no line
                    DelimReaderLog.debug("DelimReader: NONE", .{});
                    self.slice = self.buffer[0..];
                    self.slice.len = try self.reader.read(self.buffer[0..]);
                    if (self.slice.len == 0) {
                        return null;
                    }
                }
                const delim_index: usize = self.nextDelimIndex() orelse 0;
                if (delim_index == 0) {
                    // Contains partial line
                    DelimReaderLog.debug("DelimReader: PART", .{});
                    // rotate buffer
                    const rotateSize = self.slice.len;
                    std.mem.copyForwards(u8, self.buffer[0..], self.slice);
                    self.slice = self.buffer[0..];
                    self.slice.len = rotateSize;

                    const readcount = try self.reader.read(self.buffer[self.slice.len..]);
                    if (readcount > 0) {
                        self.slice.len += readcount;
                        continue :goto;
                    }

                    // return partial line
                    const result: []const u8 = self.buffer[0..rotateSize];
                    self.slice.len = 0;
                    return result;
                }

                // Found full line
                DelimReaderLog.debug("DelimReader: FULL", .{});
                const result: []const u8 = self.slice[0..delim_index];
                self.slice = self.slice[delim_index + 1 ..];
                return result;
            }
        }
    };
}

/// For testing purposes only. Reads all the lines in the file, without parsing them.
pub fn read(path: []const u8) !ParseResult {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var result: ParseResult = .{};

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    const fileReader = file.reader();
    const TlineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TlineReader = try TlineReader.init(allocator, fileReader);
    defer lineReader.deinit();

    lineloop: while (try lineReader.next()) |line| {
        if (line[0] == '#') {
            std.log.debug("skipped line: '{s}'", .{line});
            continue :lineloop;
        }

        result.lineCount += 1;
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}

        const keystr: []const u8 = line[0..splitIndex];
        const valstr: []const u8 = line[(splitIndex + 1)..];
        std.log.info("line{d}: {s}, k: {s}, v: {s}", .{ line, keystr, valstr });
        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr[valstr.len - 3] == '.');
        std.debug.assert(line.len >= 5);
        std.debug.assert(line[splitIndex] == ';');
    }
    return result;
}

pub fn parse(path: []const u8, comptime print_result: bool) !ParseResult {
    var result: ParseResult = .{};
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    const fileReader = file.reader();
    const TlineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TlineReader = try TlineReader.init(allocator, fileReader);
    defer lineReader.deinit();

    // variables used for parsing
    const mapCount: comptime_int = 64;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.init(allocator);
        }
        break :blk r;
    };
    var tKey: MapKey = .{};
    var tVal: MapVal = .{ .count = 1 };

    // main loop
    lineloop: while (try lineReader.next()) |line| {
        if (line[0] == '#') {
            std.log.debug("skipped line: '{s}'", .{line});
            continue :lineloop;
        }

        result.lineCount += 1;
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}

        const valstr: []const u8 = line[(splitIndex + 1)..];
        // parsing key and value string
        tKey.set(line[0..splitIndex]);
        const mapIndex: usize = @as(usize, @intCast(tKey.buffer[0] +% tKey.len)) % mapCount; // I have tried to beat this but i cant
        const map: *TMap = &maps[mapIndex];
        const valint: Tuv = @intCast(fastIntParse(valstr));
        tVal.max = valint;
        tVal.min = valint;
        tVal.sum = valint;

        // map.addOrUpdate(&tKey, &tVal, MapVal.add);

        const keyIndex = map.indexOf(&tKey);
        if (keyIndex != null) {
            map.values[@as(usize, @intCast(keyIndex.?))].add(&tVal);
        } else {
            _ = map.addClobber(&tKey, &tVal);
        }
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>2}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey: *MapKey = &maps[i].keys[j];
            const rVal: *MapVal = &maps[i].values[j];

            // _ = maps[0].addOrUpdate(rKey, rVal, MapVal.add);

            const keyIndex = maps[0].indexOf(rKey);
            if (keyIndex != null) {
                maps[0].values[@as(usize, @intCast(keyIndex.?))].add(rVal);
            } else {
                _ = maps[0].addClobber(rKey, rVal);
            }
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k: *MapKey = &maps[0].keys[i];
            const keystr = k.get();
            const v: *MapVal = &maps[0].values[i];
            try stdout.print("{s};{d:.1};{d:.1};{d:.1}\n", .{ // NO WRAP
                keystr,
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

// ========== TESTING ==========
test "compare2" {
    const data = @import("benchmarking/data/data.zig");
    var keyList: std.ArrayList([]const u8) = try data.readTestKeys(std.testing.allocator);
    defer keyList.deinit();

    const names = keyList.items;
    var iterId: u64 = 0;
    for (1..names.len) |i| {
        const ki: MapKey = MapKey.create(names[i]);
        for (0..i) |j| {
            iterId += 1;
            const kj: MapKey = MapKey.create(names[j]);

            const cmp1_ij = MapKey.compare_valid(&ki, &kj);
            const cmp1_ji = MapKey.compare_valid(&kj, &ki);
            const cmp2_ij = MapKey.compare2(&ki, &kj);
            const cmp2_ji = MapKey.compare2(&kj, &ki);

            const v1_ij: u8 = @abs(@intFromEnum(cmp1_ij));
            const v1_ji: u8 = @abs(@intFromEnum(cmp1_ji));
            const v2_ij: u8 = @abs(@intFromEnum(cmp2_ij));
            const v2_ji: u8 = @abs(@intFromEnum(cmp2_ji));

            std.testing.expectEqual(v1_ij, v2_ij) catch |err| {
                std.log.warn("error at iteration {d}: ki: \"{s}\", kj: \"{s}\"", .{ iterId, ki.get(), kj.get() });
                return err;
            };
            std.testing.expectEqual(v1_ji, v2_ji) catch |err| {
                std.log.warn("error at iteration {d}: ki: \"{s}\", kj: \"{s}\"", .{ iterId, ki.get(), kj.get() });
                return err;
            };
        }
    }
}

test "Size and Alignment" {
    @setRuntimeSafety(false);
    const metainfo = @import("metainfo/metainfo.zig");

    metainfo.logMemInfo(MapKey);
    metainfo.logMemInfo(MapVal);
    metainfo.logMemInfo(ParseResult);
    metainfo.logMemInfo(DelimReader(fs.File.Reader, '\n', readBufferSize));
    metainfo.logMemInfo(TMap);
}
