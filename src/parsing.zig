// Semi-rewrite for simplifications sake
const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const sorted = @import("sorted/sorted.zig");
const compare = sorted.compare;
const utils = @import("utils.zig");
const linelog = std.log.scoped(.Lines);

const ProgressiveFileReader = @import("progressiveFileReader.zig").ProgressiveFileReader;
const DelimReader = @import("delimReader.zig").DelimReader;

const MapKey = @import("mapKey.zig").MapKey;

/// Type of int used in the MapVal struct
const Tival = i32;
/// Type of map used in parse function
const TMap = sorted.SSOSortedArrayMap(MapVal);
// const TMap = sorted.BRCStringSortedArrayMap(MapVal);

fn fastIntParse(comptime T: type, numstr: []const u8) T {
    comptime {
        const Ti = @typeInfo(T);
        if (Ti != .int or Ti.int.signedness != .signed) @compileError("T must be an signed integer, but was: " + @typeName(T));
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
                .float => {},
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
                .float => {},
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
                .float => {},
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

pub fn parse_respectComments(path: []const u8, comptime print_result: bool) !ParseResult {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    const fileReader = file.reader();
    const TLineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TLineReader = try TLineReader.init(std.heap.page_allocator, fileReader);
    defer lineReader.deinit();

    // variables used for parsing
    var result: ParseResult = .{};
    const mapCount: u8 = 255;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.initWithCapacity(allocator, 256);
        }
        break :blk r;
    };
    var keystr: []const u8 = undefined;
    var valstr: []const u8 = undefined;
    var tVal: MapVal = .{ .count = 1 };

    // main loop
    lineloop: while (try lineReader.next()) |line| {
        if (line[0] == '#') {
            @branchHint(std.builtin.BranchHint.cold);
            linelog.debug("skipped line: '{s}'", .{line});
            continue :lineloop;
        } else {
            @branchHint(std.builtin.BranchHint.likely);
            std.debug.assert(line.len >= 5);
            result.lineCount += 1;
            var splitIndex: usize = line.len - 4;
            while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
            std.debug.assert(line[splitIndex] == ';');

            keystr = line[0..splitIndex];
            valstr = line[(splitIndex + 1)..];
            std.log.info("line{d}: {s}, k: {s}, v: {s}", .{ result.lineCount, line, keystr, valstr });
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
            maps[mapIndex].addOrUpdateString(keystr, &tVal, MapVal.add);
        }
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>3}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = &maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k = &maps[0].keys[i];
            keystr = k.toString();
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

pub fn parse_delimReader(path: []const u8, comptime print_result: bool) !ParseResult {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    const fileReader = file.reader();
    const TLineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TLineReader = try TLineReader.init(std.heap.page_allocator, fileReader);
    defer lineReader.deinit();

    // variables used for parsing
    var result: ParseResult = .{};
    const mapCount: u8 = 255;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.initWithCapacity(allocator, 256);
        }
        break :blk r;
    };
    var keystr: []const u8 = undefined;
    var valstr: []const u8 = undefined;
    var tVal: MapVal = .{ .count = 1 };

    // main loop
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        result.lineCount += 1;
        linelog.info("line{d}: {s}", .{ result.lineCount, line });

        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        keystr = line[0..splitIndex];
        valstr = line[(splitIndex + 1)..];
        // linelog.info("line{d}: {s}, k: {s}, v: {s}", .{ result.lineCount, line, keystr, valstr });

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
        maps[mapIndex].addOrUpdateString(keystr, &tVal, MapVal.add);
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>3}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = &maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k = &maps[0].keys[i];
            keystr = k.toString();
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

pub fn parse_readAll(path: []const u8, comptime print_result: bool) !ParseResult {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read entire file
    var file: fs.File = try openFile(allocator, path);
    defer file.close();

    std.log.debug("begun reading file content", .{});

    // const stat = try file.stat();
    // const fileContent: []u8 = try std.heap.page_allocator.alloc(u8, stat.size);
    // defer std.heap.page_allocator.free(fileContent);
    // const buffer_size: usize = try file.read(fileContent);
    // const buffer: []const u8 = fileContent[0..buffer_size];

    var buffer: []const u8 = try utils.mem.readAllBytes(file, allocator);
    defer allocator.free(buffer);
    defer std.log.debug("finished reading file content", .{});

    // variables used for parsing
    var result: ParseResult = .{};
    const mapCount: u8 = 255;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.initWithCapacity(allocator, 256);
        }
        break :blk r;
    };
    var keystr: []const u8 = undefined;
    var valstr: []const u8 = undefined;
    var tVal: MapVal = .{ .count = 1 };

    // main loop
    var L: usize = 0;
    var R: usize = 1;
    while (R < buffer.len) {
        while (buffer[R] != ';') : (R += 1) {}
        std.debug.assert(buffer[R] == ';');
        keystr = buffer[L..R];
        R += 1;
        L = R;

        while (R < buffer.len and buffer[R] != '\n') : (R += 1) {}
        valstr = buffer[L..R];
        R += 1;
        L = R;

        result.lineCount += 1;
        linelog.info("line{d}: {s};{s}, k: {s}, v: {s}", .{ result.lineCount, keystr, valstr, keystr, valstr });

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
        maps[mapIndex].addOrUpdateString(keystr, &tVal, MapVal.add);
    }

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>3}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = &maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k = &maps[0].keys[i];
            keystr = k.toString();
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

pub fn parse(path: []const u8, comptime print_result: bool) !ParseResult {
    return try parse_delimReader(path, print_result);
}

pub fn parseParallel_readAll(path: []const u8, comptime print_result: bool) !ParseResult {
    const allocator = std.heap.smp_allocator;

    // Setup file reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    var reader: ProgressiveFileReader = try ProgressiveFileReader.init(allocator, file);

    // Setup splitting
    const SizedSlice = @import("sizedSlice.zig").SizedSlice(u8, u8);
    const KVPOffset = struct { key_s: SizedSlice, val_s: SizedSlice };
    const offsetCount: comptime_int = 60;
    const Toffsets: type = [offsetCount]?KVPOffset;
    var offsets: Toffsets = undefined;
    @memset(offsets[0..], null);

    // Setup maps
    var result: ParseResult = .{};
    const mapCount: comptime_int = 255;
    var maps: [mapCount]TMap = blk: {
        var r: [mapCount]TMap = undefined;
        for (0..mapCount) |i| {
            r[i] = try TMap.initWithCapacity(allocator, 256);
        }
        break :blk r;
    };
    const MergeContext = struct {
        const TSelf = @This();
        maps_ptr: *[mapCount]TMap,
        offsets_ptr: *Toffsets,
        run_ptr: *bool,

        pub fn mergeIndex(self: *TSelf, index: usize) bool {
            if (self.offsets_ptr[index] != null) {
                const offset: KVPOffset = self.offsets_ptr[index].?;
                const keystr: []u8 = offset.key_s.toSlice();
                const valstr: []u8 = offset.val_s.toSlice();
                std.debug.assert(keystr.len >= 1);
                std.debug.assert(keystr.len <= 100);
                std.debug.assert(keystr[keystr.len - 1] != ';');
                std.debug.assert(valstr.len >= 3);
                std.debug.assert(valstr.len <= 5);
                std.debug.assert(valstr[valstr.len - 2] == '.');
                std.debug.assert(valstr[0] != ';');

                // parsing key and value string
                const valint: Tival = fastIntParse(Tival, valstr);
                const tVal: MapVal = .{ .count = 1, .max = valint, .min = valint, .sum = valint };
                const mapIndex: u8 = MapKey.sumString(keystr) % mapCount;
                self.maps_ptr[mapIndex].addOrUpdateString(keystr, &tVal, MapVal.add);

                self.offsets_ptr[index] = null;
                return true;
            }
            return false;
        }

        pub fn merge(self: *TSelf) void {
            self.run_ptr.* = true;
            var offsetIndex: usize = 0;
            while (self.run_ptr.*) {
                offsetIndex *= @intFromBool(offsetIndex < self.offsets_ptr.len); // fast modulo
                const merged = self.mergeIndex(offsetIndex);
                offsetIndex = (offsetIndex + @intFromBool(merged));
            }
        }
        /// Merges every non-null offset
        pub fn mergeRemaining(self: *TSelf) void {
            for (0..self.offsets_ptr.len) |i| {
                _ = self.mergeIndex(i);
            }
        }
    };

    // start reading file on new thread
    var readThread: std.Thread = try std.Thread.spawn(.{ .allocator = allocator }, ProgressiveFileReader.read, .{&reader});
    // start map merge thread
    var runMergeThread: bool = undefined;
    var mergeContext: MergeContext = .{
        .maps_ptr = &maps,
        .offsets_ptr = &offsets,
        .run_ptr = &runMergeThread,
    };
    var mergeThread: std.Thread = try std.Thread.spawn(.{ .allocator = allocator }, MergeContext.merge, .{&mergeContext});
    // main loop
    var L: usize = 0;
    var R: usize = 1;
    var buffer: []const u8 = undefined;
    var writeSplitIdx: usize = 0;
    while (reader.isReading or R < reader.buffer.len) {
        nosuspend buffer = reader.data;
        if (R >= buffer.len or buffer.len < 4) continue;

        while (R < buffer.len and buffer[R] != ';') : (R += 1) {}
        if (R >= buffer.len or buffer[R] != ';') continue;
        const key_s = SizedSlice.fromSlice(buffer[L..R]);
        R += 1;
        L = R;

        while (R < buffer.len and buffer[R] != '\n') : (R += 1) {}
        const val_s = SizedSlice.fromSlice(buffer[L..R]);
        R += 1;
        L = R;

        result.lineCount += 1;
        linelog.info("line{d}: {s};{s}, k: {s}, v: {s}", .{ result.lineCount, key_s, val_s, key_s, val_s });

        // Wait for the merge thread to read and merge this index
        writeSplitIdx *= @intFromBool(writeSplitIdx < offsets.len); // fast modulo
        while (offsets[writeSplitIdx] != null) {}
        offsets[writeSplitIdx] = KVPOffset{ .key_s = key_s, .val_s = val_s };
        writeSplitIdx += 1;
    }

    readThread.join();
    runMergeThread = false;
    mergeThread.join();
    mergeContext.mergeRemaining();

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>3}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = &maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k = &maps[0].keys[i];
            const keystr = k.toString();
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

pub fn parseParallel_threadpool(path: []const u8, comptime print_result: bool) !ParseResult {
    comptime if (builtin.single_threaded) @compileError("This method doesnt work in single threaded mode");
    const allocator = std.heap.smp_allocator;

    // Setup reading
    var file: fs.File = try openFile(allocator, path);
    defer file.close();
    const fileReader = file.reader();
    const TLineReader = DelimReader(@TypeOf(fileReader), '\n', readBufferSize);
    var lineReader: TLineReader = try TLineReader.init(std.heap.page_allocator, fileReader);
    defer lineReader.deinit();

    // variables used for parsing
    var result: ParseResult = ParseResult{};

    const mapCount: u8 = 100;
    var maps: [mapCount]TMap = undefined;
    var map_locks: [mapCount]std.Thread.Mutex = undefined;
    for (0..mapCount) |i| {
        maps[i] = try TMap.init(allocator);
        map_locks[i] = std.Thread.Mutex{};
    }

    var pool: std.Thread.Pool = undefined;
    const max_thread_count = try std.Thread.getCpuCount();
    try pool.init(std.Thread.Pool.Options{
        .allocator = allocator,
        .n_jobs = std.math.clamp(mapCount, 2, max_thread_count),
    });
    defer pool.deinit();

    const workFn = struct {
        pub fn f(alc: std.mem.Allocator, line_clone: []const u8, map: *TMap, lock: *std.Thread.Mutex) void {
            nosuspend {
                var splitIndex: usize = line_clone.len - 4;
                while (line_clone[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
                std.debug.assert(line_clone[splitIndex] == ';');

                const keystr = line_clone[0..splitIndex];
                const valstr = line_clone[(splitIndex + 1)..];

                std.debug.assert(keystr.len >= 1);
                std.debug.assert(keystr.len <= 100);
                std.debug.assert(keystr[keystr.len - 1] != ';');
                std.debug.assert(valstr.len >= 3);
                std.debug.assert(valstr.len <= 5);
                std.debug.assert(valstr[valstr.len - 2] == '.');
                std.debug.assert(valstr[0] != ';');

                // parsing key and value string
                const valint: Tival = fastIntParse(Tival, valstr);
                const tVal: MapVal = .{
                    .count = 1,
                    .max = valint,
                    .min = valint,
                    .sum = valint,
                };

                lock.lock();
                map.addOrUpdateString(keystr, &tVal, MapVal.add);
                lock.unlock();

                alc.free(line_clone);
            }
        }
    }.f;

    // main loop
    var wg: std.Thread.WaitGroup = .{};
    var mapIndex: usize = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        result.lineCount += 1;
        linelog.info("line{d}: {s}", .{ result.lineCount, line });

        const line_clone: []const u8 = try utils.mem.clone(u8, allocator, line);
        const lock: *std.Thread.Mutex = &map_locks[mapIndex];
        pool.spawnWg(&wg, workFn, .{ allocator, line_clone, &maps[mapIndex], lock });
        mapIndex = (mapIndex + 1) % mapCount;
    }

    wg.wait();

    // Adding all the maps to maps[0]
    for (1..mapCount) |i| {
        std.log.debug("map[{d:0>3}] keycount = {d}", .{ i, maps[i].count });
        for (0..maps[i].count) |j| {
            const rKey = &maps[i].keys[j];
            const rVal = &maps[i].values[j];
            maps[0].addOrUpdate(rKey, rVal, MapVal.add);
        }
        maps[i].deinit();
    }

    if (print_result) {
        const stdout = std.io.getStdOut().writer();
        for (0..maps[0].count) |i| {
            const k = &maps[0].keys[i];
            const keystr = k.toString();
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
    // return try parseParallel_readAll(path, print_result);
    // return try @call(.never_inline, parseParallel_readAll, .{ path, print_result });
    return try @call(.always_inline, parseParallel_readAll, .{ path, print_result });
}

// ========== TESTING ==========
test "fastIntParse" {
    try std.testing.expectEqual(@as(Tival, -123), fastIntParse(Tival, "-123"));
    try std.testing.expectEqual(@as(Tival, -123), fastIntParse(Tival, "-12.3"));
    try std.testing.expectEqual(@as(Tival, 123), fastIntParse(Tival, "123"));
    try std.testing.expectEqual(@as(Tival, 123), fastIntParse(Tival, "12.3"));
}

test "Size and Alignment" {
    const metainfo = @import("metainfo/metainfo.zig");
    const sso = @import("sorted/sso.zig");
    metainfo.logMemInfo(MapKey);
    metainfo.logMemInfo(MapVal);
    metainfo.logMemInfo(ParseResult);
    metainfo.logMemInfo(DelimReader(fs.File.Reader, '\n', readBufferSize));
    metainfo.logMemInfo(TMap);
    metainfo.logMemInfo(sso.SmallString);
    metainfo.logMemInfo(sso.LargeString);

    const smallSize = @sizeOf(sso.SmallString);
    const largeSize = @sizeOf(sso.LargeString);
    try std.testing.expectEqual(largeSize, smallSize);

    const smallAlignment = @alignOf(sso.SmallString);
    const largeAlignment = @alignOf(sso.LargeString);
    try std.testing.expectEqual(largeAlignment, smallAlignment);
}

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
                std.log.warn("error at iteration {d}: ki: \"{s}\", kj: \"{s}\"", .{ iterId, ki.toString(), kj.toString() });
                return err;
            };
            std.testing.expectEqual(v1_ji, v2_ji) catch |err| {
                std.log.warn("error at iteration {d}: ki: \"{s}\", kj: \"{s}\"", .{ iterId, ki.toString(), kj.toString() });
                return err;
            };
        }
    }
}
