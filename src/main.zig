const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const BRCMap: type = lib.BRCMap(131072);

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .err,
        .ReleaseSmall => .err,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        // .{ .scope = .DelimReader, .level = .err },
        // .{ .scope = .BRCMap, .level = .err },
        // .{ .scope = .Lines, .level = .err },
        // .{ .scope = .BRCHashMap, .level = .err },
    },
};

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

fn parseBlock(map: *BRCMap, block: []const u8) usize {
    var iter = std.mem.splitScalar(u8, block, '\n');
    var linecount: usize = 0;
    while (iter.next()) |line| {
        std.debug.assert(line.len >= 5);
        linecount += 1;
        const split_index: usize = std.mem.indexOfScalar(u8, line, ';') orelse @panic("line missing ';'");

        const key_str: []const u8 = line[0..split_index];
        const val_str: []const u8 = line[split_index + 1 ..];
        const val: i32 = lib.brcIntParse(val_str);
        map.addOrUpdate(key_str, val) catch |e| std.log.err("{any}{any}", .{ e, @errorReturnTrace() });
    }
    return linecount;
}

fn parseBlockMultiThread(map: *BRCMap, count: *usize, lock: *std.Thread.Mutex, block: []const u8) void {
    lock.lock();
    defer lock.unlock();
    count.* += parseBlock(map, block);
}

fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize);
    var reader: BlockReader = try BlockReader.init(path);
    defer reader.deinit();

    const threadCount = try std.Thread.getCpuCount();
    const maps: []BRCMap = try allocator.alloc(BRCMap, threadCount);
    defer allocator.free(maps);
    const counts: []usize = try allocator.alloc(usize, threadCount);
    defer allocator.free(maps);
    const locks: []std.Thread.Mutex = try allocator.alloc(std.Thread.Mutex, threadCount);
    for (0..threadCount) |i| {
        maps[i] = try BRCMap.init(allocator);
        counts[i] = 0;
        locks[i] = std.Thread.Mutex{};
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    var wg: std.Thread.WaitGroup = .{};

    const stdout = std.io.getStdOut().writer();
    var i: usize = 0;

    while (reader.next()) |block| : (i += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        const id: usize = i % threadCount;
        pool.spawnWg(&wg, parseBlockMultiThread, .{ &maps[id], &counts[id], &locks[id], block });
    }
    wg.wait();

    // Merge maps
    var count: usize = counts[0];
    for (1..maps.len) |mi| {
        const map: *BRCMap = &maps[mi];
        for (0..map.count) |ki| {
            if (map.keys[ki] != null) {
                try maps[0].addOrMerge(map.keys[ki].?, &map.values[ki].?);
            }
        }
        count += counts[mi];
        map.deinit();
    }
    defer maps[0].deinit();

    try std.fmt.format(stdout, "found {d} keys in {d} lines\n", .{ maps[0].count, count });
}

pub fn main() !void {
    var timer = try std.time.Timer.start();
    try parseFile(static_allocator, debugfilepath);
    const ns = timer.read();
    std.debug.print("parsed in {}", .{std.fmt.fmtDuration(ns)});
}
