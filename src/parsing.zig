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
const Tival = i32;
/// Type of map used in parse function
const TMap = sorted.StringSortedArrayMap(MapVal);

fn fastIntParse(comptime T: type, numstr: []const u8) T {
    comptime {
        const Ti = @typeInfo(T);
        if (Ti != .Int or Ti.Int.signedness != .signed) {
            @compileError("T must be an signed integer, but was: " + @typeName(T));
        }
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
    count: Tival = 0,
    sum: Tival = 0,
    min: Tival = std.math.maxInt(Tival),
    max: Tival = std.math.minInt(Tival),

    pub inline fn addRaw(mv: *MapVal, v: Tival) void {
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
        const valint: Tival = fastIntParse(Tival, valstr);
        tVal.max = valint;
        tVal.min = valint;
        tVal.sum = valint;

        const mapIndex: u8 = MapKey.sumString(keystr) % mapCount;
        maps[mapIndex].addOrUpdate(keystr, &tVal, MapVal.add);
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>2}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey.asSlice(), rVal, MapVal.add);
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

        const TData = struct {
            line: []u8,
        };
        const TList = std.DoublyLinkedList(TData);
        const TNode = TList.Node;

        const mapCount: u8 = 255;
        const maxRetries: u8 = 64;

        allocator: std.mem.Allocator,
        thread: std.Thread = undefined,

        readingBegunEvent: std.Thread.ResetEvent = .{},
        readingFinishedEvent: std.Thread.ResetEvent = .{},
        lastParseEvent: std.Thread.ResetEvent = .{},
        parseEvent: std.Thread.ResetEvent = .{},

        lines: TList = .{},
        linesMutex: std.Thread.Mutex = .{},
        totalLineCount: usize = 0,
        map: TMap = undefined,

        pub fn init(alc: std.mem.Allocator) !TSelf {
            return TSelf{ .allocator = alc, .map = try TMap.init(alc) };
        }

        pub fn deinit(self: *TSelf) void {
            self.map.deinit();
        }

        inline fn createData(alc: std.mem.Allocator, line: []const u8) !TData {
            var r: TData = .{ .line = try alc.alloc(u8, line.len) };
            @memcpy(r.line[0..], line[0..]);
            return r;
        }

        inline fn destroyData(alc: std.mem.Allocator, data: *TData) void {
            alc.free(data.line);
        }

        inline fn pop(self: *TSelf) ?*TNode {
            self.linesMutex.lock();
            const r = self.lines.pop();
            self.linesMutex.unlock();
            return r;
        }

        fn threadFn(self: *TSelf) void {
            self.readingBegunEvent.wait();
            while (!self.readingFinishedEvent.isSet()) {
                while (self.pop()) |node| {
                    self.parseEvent.set();
                    const line = node.data.line;
                    if (line[0] != '#') {
                        self.totalLineCount += 1;
                        linelog.info("line{d}: {s}", .{ self.totalLineCount, line });
                        var splitIdx = line.len - 4;
                        while (line[splitIdx] != ';' and splitIdx > 0) : (splitIdx -= 1) {}
                        const keystr: []const u8 = line[0..splitIdx];
                        const valstr: []const u8 = line[(splitIdx + 1)..];
                        const valint: Tival = @intCast(fastIntParse(Tival, valstr));
                        const tKey: MapKey = MapKey.create(keystr);
                        const tVal: MapVal = .{ .count = 1, .sum = valint, .max = valint, .min = valint };
                        self.map.addOrUpdate(&tKey, &tVal, MapVal.add);
                    }
                    destroyData(self.allocator, &node.data);
                    self.allocator.destroy(node);
                }
            }
            self.lastParseEvent.set();
        }

        pub fn handleLine(self: *TSelf, line: []const u8) !void {
            var node: *TNode = try self.allocator.create(TNode);
            node.data = try createData(self.allocator, line);

            if (self.lines.len > 0) {
                self.parseEvent.wait();
            }
            self.lines.prepend(node);
            self.readingBegunEvent.set();
        }

        pub fn start(self: *TSelf) !void {
            self.thread = try std.Thread.spawn(.{ .allocator = self.allocator }, threadFn, .{self});
        }

        pub fn wait(self: *TSelf) void {
            self.readingBegunEvent.set();
            self.readingFinishedEvent.set();
            self.lastParseEvent.wait();
            self.thread.join();
        }
    };

    const threadCount: usize = 15;
    var factoryAllocators: [threadCount]std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var factories: [threadCount]ThreadFactory = undefined;
    inline for (0..threadCount) |i| {
        factoryAllocators[i] = .{};
        factories[i] = try ThreadFactory.init(factoryAllocators[i].allocator());
        try factories[i].start();
    }

    std.log.debug("begun reading", .{});
    var fId: usize = 0;
    while (try lineReader.next()) |line| {
        try factories[fId].handleLine(line);
        fId = (fId + 1) % factories.len;
    }
    lineReader.deinit();
    file.close();
    std.log.debug("finished reading", .{});

    std.log.debug("begun waiting and merging", .{});
    var result: ParseResult = .{
        .uniqueKeys = 0,
        .lineCount = 0,
    };
    var map: TMap = try TMap.init(allocator);
    defer map.deinit();
    inline for (0..threadCount) |i| {
        factories[i].wait();
        map.join(&factories[i].map, MapVal.add);
        result.lineCount += factories[i].totalLineCount;
        factories[i].deinit();
        _ = factoryAllocators[i].deinit();
    }
    result.uniqueKeys = map.count;
    std.log.debug("finished waiting", .{});

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

    return result;
}

// ========== TESTING ==========
test "compare" {
    const data = @import("benchmarking/data/data.zig");
    var keyList: std.ArrayList([]const u8) = try data.readCityNames(std.testing.allocator);
    defer keyList.deinit();

    const len = std.math.clamp(keyList.items.len, 0, 256);
    const names = keyList.items[0..len];
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

test "fastIntParse" {
    try std.testing.expectEqual(@as(Tival, -123), fastIntParse(Tival, "-123"));
    try std.testing.expectEqual(@as(Tival, -123), fastIntParse(Tival, "-12.3"));
    try std.testing.expectEqual(@as(Tival, 123), fastIntParse(Tival, "123"));
    try std.testing.expectEqual(@as(Tival, 123), fastIntParse(Tival, "12.3"));
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
