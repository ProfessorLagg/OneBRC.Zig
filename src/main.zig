const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const BRCMap: type = lib.BRCMap(131072);
const sso = lib.sso;
const Stat = lib.Stat;
const sorting = lib.sorting;
const BlockSplitter = lib.SplitIterator('\n');

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

fn parseBlock(map: *BRCMap, block: []const u8) void {
    // var iter = std.mem.splitScalar(u8, block, '\n');
    var iter: BlockSplitter = .{ .buffer = block };
    while (iter.next()) |line| {
        std.debug.assert(line.len >= 5);
        std.debug.assert(line[0] != '\n');
        std.debug.assert(line[line.len - 1] != '\n');

        const split_index: usize = b: {
            // The ; can only be in the following positions: len - 4, len - 5, len - 6
            if (line[line.len - 4] == ';') break :b line.len - 4;
            if (line[line.len - 5] == ';') break :b line.len - 5;
            if (line[line.len - 6] == ';') break :b line.len - 6;
            unreachable;
        };
        const key_str: []const u8 = line[0..split_index];
        const val_str: []const u8 = line[split_index + 1 ..];
        std.debug.assert(key_str.len >= 1);
        std.debug.assert(key_str.len <= 100);
        std.debug.assert(val_str.len >= 3);
        std.debug.assert(val_str.len <= 5);

        const val: i32 = lib.brcIntParse(val_str);
        map.addOrUpdate(key_str, val) catch |e| std.log.err("{any}{any}", .{ e, @errorReturnTrace() });
    }
}

inline fn getMaxBlockCount(comptime maxBlockSize: comptime_int, fileSize: u64) u64 {
    const maxLineLen: comptime_int = 107;
    const minBlockSize: u64 = comptime maxBlockSize - maxLineLen;
    const a: u64 = @divFloor(fileSize, minBlockSize);
    const b: u64 = @intFromBool(a * minBlockSize != fileSize);
    return a + b;
}

fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize, '\n');
    var reader: BlockReader = try BlockReader.init(path); // deinit is at the end of the function

    const mapCount = getMaxBlockCount(blocksize, reader.fileSize());
    const maps: []BRCMap = try allocator.alloc(BRCMap, mapCount);
    defer allocator.free(maps);
    for (0..mapCount) |i| maps[i] = try BRCMap.init(allocator);

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = (try std.Thread.getCpuCount()) - 1 });
    var wg: std.Thread.WaitGroup = .{};
    var blockId: usize = 0;
    while (reader.next()) |block| : (blockId += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        if (reader.remain() == 0) {
            parseBlock(&maps[blockId], block);
        } else {
            pool.spawnWg(&wg, parseBlock, .{ &maps[blockId], block });
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

fn printBrcMap(map: *const BRCMap) !void {
    // Sort the entries
    const Entry = struct {
        const Self = @This();
        key: []const u8,
        val: *const Stat,
        pub fn compareR(a: *const Self, b: *const Self) sorting.CompareResult {
            return @call(.always_inline, sorting.compareStrings, .{ a.key, b.key });
        }
    };
    const entries: []Entry = try map.allocator.alloc(Entry, map.count);
    defer map.allocator.free(entries);
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
    const rawbuf: []u8 = try map.allocator.alloc(u8, entries.len * 120); // longest entry string is 120
    defer map.allocator.free(rawbuf);
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
    // try bench(filepath);
    try parseFile(static_allocator, filepath);
}
