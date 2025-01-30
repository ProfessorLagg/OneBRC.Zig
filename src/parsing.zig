// Semi-rewrite for simplifications sake
const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const sorted = @import("sorted/sorted.zig");
const compare = sorted.compare;
const linelog = std.log.scoped(.Lines);
const DelimReader = @import("delimReader.zig").DelimReader;

const MapKey = @import("mapKey.zig").MapKey;

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
inline fn fastIntParseT(comptime T: type, numstr: []const u8) T {
    comptime {
        const Ti = @typeInfo(T);
        if (Ti != .Int or Ti.Int.signedness != .signed) {
            @compileError("Invalid int type: " ++ @typeName(T));
        }
    }
    const isNegative: bool = numstr[0] == '-';
    const isNegativeInt: usize = @intFromBool(isNegative);

    var result: T = 0;
    var m: T = 1;
    var i: T = @as(T, @intCast(numstr.len)) - 1;
    while (i >= isNegativeInt) {
        const ci: T = @intCast(numstr[@as(usize, @intCast(i))]);
        const valid: bool = ci >= 48 and ci <= 57;
        const validInt: T = @intFromBool(valid);
        const invalidInt: T = @intFromBool(!valid);
        const value: T = validInt * ((ci - 48) * m); // '0' = 48
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

const LineBuffer = struct { // NO FOLD
    const TSelf = @This();
    const size: comptime_int = 106;
    bytes: [size]u8 = undefined,
    len: u8 = 0,

    pub inline fn create(line: []const u8) TSelf {
        var r: TSelf = .{};
        r.set(line);
        return r;
    }
    pub inline fn set(self: *TSelf, line: []const u8) void {
        self.len = @max(size, @as(@TypeOf(self.len), @intCast(line.len)));
        std.mem.copyForwards(u8, &self.bytes, line);
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

const readBufferSize: comptime_int = 4096 * @sizeOf(usize); //  4096 * 256 = 1mb
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
            linelog.debug("skipped line: '{s}'", .{line});
            continue :lineloop;
        }
        result.lineCount += 1;

        linelog.info("line{d}: {s}", .{ result.lineCount, line });

        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        const keystr: []const u8 = line[0..splitIndex];
        const valstr: []const u8 = line[(splitIndex + 1)..];
        linelog.info("line{d}: {s}, k: {s}, v: {s}", .{ result.lineCount, line, keystr, valstr });
        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr[valstr.len - 2] == '.');
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
    const TLineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TLineReader = try TLineReader.init(std.heap.page_allocator, fileReader);
    defer lineReader.deinit();

    // variables used for parsing
    const mapCount: u8 = 255;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.init(allocator);
        }
        break :blk r;
    };
    var keystr: []const u8 = undefined;
    var valstr: []const u8 = undefined;
    var tKey: MapKey = .{};
    var tVal: MapVal = .{ .count = 1 };

    // main loop
    lineloop: while (try lineReader.next()) |line| {
        if (line[0] == '#') {
            linelog.debug("skipped line: '{s}'", .{line});
            continue :lineloop;
        }
        std.debug.assert(line.len >= 5);
        result.lineCount += 1;
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        keystr = line[0..splitIndex];
        valstr = line[(splitIndex + 1)..];
        linelog.info("line{d}: {s}, k: {s}, v: {s}", .{ result.lineCount, line, keystr, valstr });
        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        // parsing key and value string
        tKey.set(keystr);
        const valint: Tuv = @intCast(fastIntParse(valstr));
        tVal.max = valint;
        tVal.min = valint;
        tVal.sum = valint;

        const mapIndex: u8 = tKey.sum % mapCount;
        maps[mapIndex].addOrUpdate(&tKey, &tVal, MapVal.add);
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>2}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey: *MapKey = &maps[i].keys[j];
            const rVal: *MapVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k: *MapKey = &maps[0].keys[i];
            keystr = k.get();
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

pub fn parseParallel(path: []const u8, comptime print_result: bool) !ParseResult {
    comptime {
        if (builtin.single_threaded) {
            @compileError("This method doesnt work in single threaded mode");
        }
    }
    _ = &print_result;
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    const fileReader = file.reader();
    const TLineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TLineReader = try TLineReader.init(std.heap.page_allocator, fileReader);

    // Setup threads
    const ThreadFactory = struct {
        const TSelf = @This();
        const mapCount: u8 = 255;
        const maxRetries: u8 = 64;

        allocator: std.mem.Allocator,
        threadPool: std.Thread.Pool,
        wg: std.Thread.WaitGroup = .{},
        maps: [mapCount]TMap = undefined,
        mapLocks: [mapCount]std.Thread.Mutex = undefined,
        mapsMerged: bool = false,

        pub fn init(alc: std.mem.Allocator) !TSelf {
            var r = TSelf{ // NO FOLD
                .allocator = alc,
                .threadPool = blk: {
                    var r: std.Thread.Pool = undefined;
                    try r.init(.{ .allocator = alc });
                    break :blk r;
                },
            };

            for (0..mapCount) |i| {
                r.mapLocks[i] = .{};
                r.maps[i] = try TMap.init(alc);
            }

            return r;
        }
        pub fn deinit(self: *TSelf) void {
            self.threadPool.mutex.lock();
            self.threadPool.is_running = false;
            self.threadPool.mutex.unlock();
            self.threadPool.cond.broadcast();
            for (self.threadPool.threads) |thread| {
                thread.detach();
            }
            self.threadPool.allocator.free(self.threadPool.threads);
            inline for (0..mapCount) |i| {
                self.maps[i].deinit();
            }
        }

        fn threadFn(self: *TSelf, line: []const u8) void {
            var splitIdx = line.len - 4;
            while (line[splitIdx] != ';' and splitIdx > 0) : (splitIdx -= 1) {}
            const keystr: []const u8 = line[0..splitIdx];
            const valstr: []const u8 = line[(splitIdx + 1)..];
            const valint: Tuv = @intCast(fastIntParse(valstr));
            const tKey: MapKey = MapKey.create(keystr);
            const tVal: MapVal = .{ .count = 1, .sum = valint, .max = valint, .min = valint };
            const mapIndex: u8 = tKey.sum % mapCount;

            self.mapLocks[mapIndex].lock();
            self.maps[mapIndex].addOrUpdate(&tKey, &tVal, MapVal.add);
            self.mapLocks[mapIndex].unlock();

            self.allocator.free(line);
        }

        pub fn handleLine(self: *TSelf, line: []const u8) !bool {
            if (line[0] == '#') {
                return false;
            }
            var linecopy: []u8 = try self.allocator.alloc(u8, line.len);
            @memcpy(linecopy[0..], line[0..]);
            self.threadPool.spawnWg(&self.wg, threadFn, .{ self, linecopy });
            return true;
        }
        pub fn mergeMaps(self: *TSelf) *const TMap {
            inline for (1..mapCount) |i| {
                std.log.debug("map[{d:0>2}] keycount = {d}", .{ i, self.maps[i].count });
                for (0..self.maps[i].count) |j| {
                    const rKey: *MapKey = &self.maps[i].keys[j];
                    const rVal: *MapVal = &self.maps[i].values[j];
                    self.maps[0].addOrUpdate(rKey, rVal, MapVal.add);
                }
            }
            self.mapsMerged = true;
            return &self.maps[0];
        }
        pub fn wait(self: *TSelf) void {
            self.threadPool.waitAndWork(&self.wg);
        }
    };

    var factory: ThreadFactory = try ThreadFactory.init(allocator);
    var result: ParseResult = .{};

    std.log.debug("begun reading", .{});
    while (try lineReader.next()) |line| {
        if (try factory.handleLine(line)) {
            result.lineCount += 1;
            linelog.info("line{d}: {s}", .{ result.lineCount, line });
        }
    }
    lineReader.deinit();
    file.close();
    std.log.debug("finished reading", .{});

    std.log.debug("begun waiting", .{});
    factory.wait();
    std.log.debug("finished waiting", .{});

    std.log.debug("begun merging", .{});
    const map = factory.mergeMaps();
    std.log.debug("finished merging", .{});
    result.uniqueKeys = map.count;

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..map.count) |i| {
            const k: *MapKey = &map.keys[i];
            const v: *MapVal = &map.values[i];
            try stdout.print("{s};{d:.1};{d:.1};{d:.1}\n", .{ // NO WRAP
                k.get(),
                v.getMin(f64),
                v.getMean(f64),
                v.getMax(f64),
            });
        }
    }

    std.log.debug("begun factory deinit", .{});
    factory.deinit();
    std.log.debug("finished factory deinit", .{});
    return result;
}

// ========== TESTING ==========
test "compare" {
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
            const cmp2_ij = MapKey.compare(&ki, &kj);
            const cmp2_ji = MapKey.compare(&kj, &ki);

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
