const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const BRCmapCapacity: comptime_int = 1 << 16;
const BRCMap: type = lib.BRCMap(BRCmapCapacity);
const BRCMapUnmanaged: type = lib.BRCMapUnmanaged(BRCmapCapacity);
const sso = lib.sso;
const Stat = lib.Stat;
const sorting = lib.sorting;
const LineSplitter = lib.LineSplitter;
const ResetEvent = std.Thread.ResetEvent;

// following files have at most 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000.txt";

// following files have 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const static_allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

fn parseBlockUnmanaged(map: *BRCMapUnmanaged, block: []const u8) void {
    // var iter = std.mem.splitScalar(u8, block, '\n');
    var iter: LineSplitter = .{ .buffer = block };
    while (iter.next()) |line| {
        std.debug.assert(line.len >= 5);
        std.debug.assert(line[0] != '\n');
        std.debug.assert(line[line.len - 1] != '\n');

        // TODO this turns into to jumps. I can probably use some inline asm cmov to massively improve performance
        const split_index: usize = b: {
            @setRuntimeSafety(false);
            const left: usize = line.len - @min(line.len, 6);
            const r: usize = (@intFromBool(line[left] == ';') * left) + (@intFromBool(line[left + 1] == ';') * (left + 1)) + (@intFromBool(line[left + 2] == ';') * (left + 2));
            break :b r;
        };
        const key_str: []const u8 = line[0..split_index];
        const val_str: []const u8 = line[split_index + 1 ..];
        std.debug.assert(key_str.len >= 1);
        std.debug.assert(key_str.len <= 100);
        std.debug.assert(val_str.len >= 3);
        std.debug.assert(val_str.len <= 5);

        const val: i32 = lib.brcIntParse(val_str);
        map.addOrUpdate(key_str, val);
    }
}

fn parseBlock(map: *BRCMap, block: []const u8) void {
    @call(.always_inline, parseBlockUnmanaged, .{ &map.unmanaged, block });
}

inline fn getMaxBlockCount(comptime maxBlockSize: comptime_int, fileSize: u64) u64 {
    const maxLineLen: comptime_int = 107;
    const minBlockSize: u64 = comptime maxBlockSize - maxLineLen;
    const a: u64 = @divFloor(fileSize, minBlockSize);
    const b: u64 = @intFromBool(a * minBlockSize != fileSize);
    return a + b;
}

inline fn parseFile_v1(allocator: std.mem.Allocator, path: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize, '\n');
    var reader: BlockReader = try BlockReader.init(path); // deinit is at the end of the function

    const mapCount = getMaxBlockCount(blocksize, reader.fileSize());
    const maps: []BRCMap = try allocator.alloc(BRCMap, mapCount);
    defer allocator.free(maps);
    for (0..mapCount) |i| maps[i] = try BRCMap.init(allocator);

    const cpuCount: usize = @min((try std.Thread.getCpuCount()) - 1, lib.getAffinityCpuCount());
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = cpuCount });
    var wg: std.Thread.WaitGroup = .{};
    var blockId: usize = 0;
    while (reader.next()) |block| : (blockId += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        if (reader.remain() == 0) {
            parseBlockUnmanaged(&maps[blockId], block);
        } else {
            pool.spawnWg(&wg, parseBlockUnmanaged, .{ &maps[blockId], block });
        }
    }
    wg.wait();

    // Merge maps
    // TODO Multithread merging maps
    for (1..maps.len) |mi| {
        const map: *BRCMap = &maps[mi];
        for (0..map.keys.len) |ki| {
            if (map.keys[ki].notEmpty()) {
                try maps[0].addOrMerge(map.keys[ki].get(), &map.values[ki]);
            }
        }
        map.deinit();
    }
    defer maps[0].deinit();
    try printBrcMap(&maps[0]);

    defer reader.deinit();
}

inline fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize, '\n');
    const ThreadContext = struct {
        const Self = @This();
        hasData: ResetEvent,
        block: []const u8,
        map: BRCMapUnmanaged,

        fn init(self: *Self) !void {
            self.hasData = .{};
            self.block.ptr = @ptrFromInt(@sizeOf(u8));
            self.block.len = 0;
            self.map = try BRCMapUnmanaged.init(allocator);
        }
        fn initMany(count: usize) ![]Self {
            const result: []Self = try allocator.alloc(Self, count);
            for (0..result.len) |i| try result[i].init();
            return result;
        }
        fn deinit(self: *Self) void {
            self.map.deinit(allocator);
        }

        fn run(self: *Self) void {
            self.hasData.wait();
            defer self.hasData.reset();
            if (self.block.len > 0) parseBlockUnmanaged(&self.map, self.block);
        }

        fn set(self: *Self, block: []const u8) void {
            self.block = block;
            self.hasData.set();
        }
        fn setCancel(self: *Self) void {
            self.block.len = 0;
            self.hasData.set();
        }
    };
    var reader: BlockReader = try BlockReader.init(path); // deinit is at the end of the function

    const maxBlockCount = getMaxBlockCount(blocksize, reader.fileSize());
    const contexts: []ThreadContext = try ThreadContext.initMany(maxBlockCount);
    defer allocator.free(contexts);
    // Start the tasks
    for (contexts) |*ctx| (try std.Thread.spawn(.{}, ThreadContext.run, .{ctx})).detach();

    var id: usize = 0;
    while (reader.next()) |block| : (id += 1) {
        std.debug.assert(id < contexts.len);
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        contexts[id].set(block);
    }

    // cancel the remaining contexts
    while (id < contexts.len) : (id += 1) contexts[id].setCancel();

    // wait for all contexts to finish
    for (contexts) |*ctx| {
        while (ctx.hasData.isSet()) {}
    }

    // merging maps
    const finalcontext: *ThreadContext = &contexts[0];
    defer finalcontext.deinit();
    const finalmap: *BRCMapUnmanaged = &finalcontext.map;
    for (contexts[1..]) |*ctx| {
        if (ctx.block.len > 0) finalmap.merge(&ctx.map);
        ctx.deinit();
    }

    try printBrcMapUnmanaged(allocator, finalmap);
    defer reader.deinit();
}

fn parseFile_v3(allocator: std.mem.Allocator, path: []const u8) !void {
    var mappedFile = try lib.MappedFile.init(path);
    defer mappedFile.deinit();

    const ThreadContext = struct {
        const Self = @This();
        finished: ResetEvent,
        blockptr: ?[*]const u8,
        blocklen: usize,
        map: BRCMapUnmanaged,

        fn init(self: *Self, alc: std.mem.Allocator) !void {
            self.finished = .{};
            self.blockptr = null;
            self.blocklen = 0;
            self.map = try BRCMapUnmanaged.init(alc);
        }
        fn initMany(count: usize, alc: std.mem.Allocator) ![]Self {
            const result: []Self = try alc.alloc(Self, count);
            for (result) |*ctx| try ctx.init(alc);
            return result;
        }
        fn deinit(self: *Self, alc: std.mem.Allocator) void {
            self.map.deinit(alc);
        }

        fn getBlock(taskIndex: usize, blocksize: usize, bytes: []const u8) []const u8 {
            var start: usize = taskIndex * blocksize;
            if (start >= bytes.len) return std.mem.zeroes([]const u8);
            startLoop: while (start > 0) {
                if (bytes[start] == '\n') {
                    start += 1;
                    break :startLoop;
                }
                start -= 1;
            }
            var end: usize = @min(bytes.len, (taskIndex + 1) * blocksize);
            if (end < bytes.len) {
                while (end > start and bytes[end] != '\n') : (end -= 1) {}
            }
            return bytes[start..end];
        }

        fn run(self: *Self, taskIndex: usize, blocksize: usize, bytes: []const u8) void {
            defer self.finished.set();
            const block = getBlock(taskIndex, blocksize, bytes);
            if (block.len > 0) {
                self.blocklen = @intCast(block.len);
                self.blockptr = block.ptr;
                std.debug.assert(block[0] != '\n');
                std.debug.assert(block[block.len - 1] != '\n');
                parseBlockUnmanaged(&self.map, block);
            }
        }
    };

    const threadCount: usize = lib.getAffinityCpuCount();
    const blocksize: usize = try std.math.divCeil(usize, mappedFile.slice.len, threadCount);

    const contexts: []ThreadContext = try ThreadContext.initMany(threadCount, allocator);
    defer allocator.free(contexts);
    // Start the tasks
    for (contexts, 0..contexts.len) |*ctx, id| (try std.Thread.spawn(.{}, ThreadContext.run, .{ ctx, id, blocksize, mappedFile.slice })).detach();

    // wait for all contexts to finish
    for (contexts) |*ctx| ctx.finished.wait();

    // merging maps
    const finalcontext: *ThreadContext = &contexts[0];
    defer finalcontext.deinit(allocator);
    const finalmap: *BRCMapUnmanaged = &finalcontext.map;
    for (contexts[1..]) |*ctx| {
        if (ctx.blocklen > 0) finalmap.merge(&ctx.map);
        ctx.deinit(allocator);
    }

    try printBrcMapUnmanaged(allocator, finalmap);
}

fn printBrcMapUnmanaged(allocator: std.mem.Allocator, map: *BRCMapUnmanaged) !void {
    // Sort the entries
    const Entry = struct {
        const Self = @This();
        key: []const u8,
        val: *const Stat,
        pub fn compareR(a: *const Self, b: *const Self) sorting.CompareResult {
            return @call(.always_inline, sorting.compareStrings, .{ a.key, b.key });
        }
    };
    const entries: []Entry = try allocator.alloc(Entry, map.count);
    defer allocator.free(entries);
    var entryId: usize = 0;
    for (0..map.keys.len) |i| {
        if (map.keys[i].empty()) continue;
        entries[entryId] = Entry{
            .key = map.keys[i].get(),
            .val = &map.values[i],
        };
        entryId += 1;
    }
    sorting.insertionSortR(Entry, Entry.compareR, entries);

    // Print the output
    const rawbuf: []u8 = try allocator.alloc(u8, entries.len * 120); // longest entry string is 120
    defer allocator.free(rawbuf);
    var buf: []u8 = rawbuf[0..];
    buf[0] = '{';
    buf = buf[1..];
    var rem: usize = map.count;
    for (entries) |e| {
        if (rem < entries.len) {
            buf[0] = ',';
            buf[1] = ' ';
            buf = buf[2..];
        }
        const record = try std.fmt.bufPrint(buf, "{s}={d:.1}/{d:.1}/{d:.1}", .{
            e.key,
            e.val.minF(),
            e.val.meanF(),
            e.val.maxF(),
        });
        buf = buf[record.len..];
        rem -= 1;
    }
    buf[0] = '}';
    buf = buf[1..];
    const stdout = std.io.getStdOut();
    _ = try stdout.write(rawbuf[0..(rawbuf.len - buf.len)]);
}

fn printBrcMap(map: *const BRCMap) !void {
    try printBrcMapUnmanaged(map.allocator, &map.unmanaged);
}

inline fn bench(filepath: []const u8) !void {
    const stderr = std.io.getStdErr().writer();

    try std.fmt.format(stderr, "Parsing file: {s}\n", .{filepath});

    const fileSize = (try (try std.fs.cwd().openFile(filepath, .{})).stat()).size;
    var timer = try std.time.Timer.start();
    try parseFile(static_allocator, filepath);
    const ns = timer.read();
    const ns_f: f64 = @floatFromInt(ns);
    const s_f: f64 = ns_f / @as(f64, @floatFromInt(std.time.ns_per_s));
    const fileSize_f: f64 = @floatFromInt(fileSize);
    const perf_f: f64 = @round(fileSize_f / s_f);
    const perf: u64 = @intFromFloat(perf_f);

    try std.fmt.format(stderr, "\n\nparsed {} in {} at {}/s\n", .{
        std.fmt.fmtIntSizeBin(fileSize),
        std.fmt.fmtDuration(ns),
        std.fmt.fmtIntSizeBin(perf),
    });
}
pub fn main() !void {
    const args = try std.process.argsAlloc(static_allocator);
    defer std.process.argsFree(static_allocator, args);
    const filepath = if (args.len == 2) args[1] else debugfilepath;
    //try bench(filepath);
    try parseFile(static_allocator, filepath);
    //try debug();
    //try debug_hash();
    _ = &filepath;
}

fn debug() !void {
    const xormask: u32 = comptime b: {
        var r: u32 = 0;
        const rb: *[4]u8 = std.mem.asBytes(&r);
        @memset(rb[0..], ';');
        break :b r;
    };

    std.debug.print("xormask: 0x{x:0>16}", .{xormask});
}
fn debug_hash() !void {
    const List = std.ArrayList([]const u8);
    const allocator: std.mem.Allocator = static_allocator;

    const capacity: comptime_int = comptime 1 << 17;
    // const capacity: comptime_int = comptime 1024 * 1024;
    const count: comptime_int = 10_000;

    const rawCities = @embedFile("cities.txt");
    const cities: [][]const u8 = try lib.splitScalarToArray(u8, rawCities, '\n', allocator);
    defer allocator.free(cities);

    // var prng = std.Random.DefaultPrng.init(@truncate(@abs(std.time.nanoTimestamp())));
    var prng = std.Random.DefaultPrng.init(2025_09_01);
    const rand = prng.random();
    rand.shuffle([]const u8, cities);

    var keys: [][]const u8 = try static_allocator.alloc([]const u8, capacity);
    defer static_allocator.free(keys);
    for (0..capacity) |i| keys[i].len = 0;

    const Context = struct {
        fn getKeyHash(key: []const u8) u64 {
            return std.hash.XxHash3.hash(0, key);
        }

        fn getBaseIndex(key: []const u8) usize {
            const hash: usize = getKeyHash(key);
            //return hash & comptime (capacity - 1);
            return hash % capacity;
        }

        fn findKeyIndex_linear(ks: [][]const u8, k: []const u8, collision_counter: *usize) usize {
            const base_index: usize = getBaseIndex(k);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset) % capacity;
                if (ks[index].len == 0) return index;
                collision_counter.* += 1;
            }
            unreachable;
        }

        fn findKeyIndex_quadratic(ks: *[capacity][]const u8, k: []const u8, collision_counter: *usize) usize {
            const base_index: usize = getBaseIndex(k);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset + offset * offset) % capacity;
                if (ks[index].len == 0) return index;
                collision_counter.* += 1;
            }
            unreachable;
        }

        fn listLessThan(_: @TypeOf(.{}), a: List, b: List) bool {
            return a.items.len > b.items.len;
        }
    };

    var collisionCount: usize = 0;
    for (cities[0..count]) |city| {
        keys[Context.findKeyIndex_linear(keys, city, &collisionCount)] = city;
    }

    const stderr = std.io.getStdErr().writer();
    const collisionRate: f64 = (@as(f64, @floatFromInt(collisionCount)) / @as(f64, @floatFromInt(count))) * 100.0;
    const loadFactor: f64 = @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(capacity)) * 100.0;
    try std.fmt.format(stderr, "collisions: {d} / {d} ({d:.2}%) | LF: {d} / {d} = {d:.2}%", .{
        collisionCount,
        count,
        @round(collisionRate * 100.0) / 100.0,
        count,
        capacity,
        @round(loadFactor * 100.0) / 100.0,
    });
}
