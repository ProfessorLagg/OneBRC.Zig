const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const BRCMap: type = lib.BRCMap(131072);

// pub const std_options: std.Options = .{
//     // Set the log level to info to .debug. use the scope levels instead
//     .log_level = switch (builtin.mode) {
//         .Debug => .debug,
//         .ReleaseSafe => .err,
//         .ReleaseSmall => .err,
//         .ReleaseFast => .err,
//     },
//     .log_scope_levels = &[_]std.log.ScopeLevel{
//         // .{ .scope = .DelimReader, .level = .err },
//         // .{ .scope = .BRCMap, .level = .err },
//         // .{ .scope = .Lines, .level = .err },
//         // .{ .scope = .BRCHashMap, .level = .err },
//     },
// };

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

fn parseBlockMultiThread(map: *BRCMap, lock: *std.Thread.Mutex, block: []const u8) void {
    lock.lock();
    defer lock.unlock();
    _ = parseBlock(map, block);
}

fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize);
    var reader: BlockReader = try BlockReader.init(path);
    defer reader.deinit();

    const threadCount = (try std.Thread.getCpuCount()) - 1;

    const mapCount = threadCount + 2;
    const maps: []BRCMap = try allocator.alloc(BRCMap, mapCount);
    defer allocator.free(maps);
    const locks: []std.Thread.Mutex = try allocator.alloc(std.Thread.Mutex, mapCount);
    for (0..mapCount) |i| {
        maps[i] = try BRCMap.init(allocator);
        locks[i] = std.Thread.Mutex{};
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = threadCount });
    var wg: std.Thread.WaitGroup = .{};
    var i: usize = 0;
    var id: usize = undefined;
    while (reader.next()) |block| : (i += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        id = i % threadCount;
        if (reader.remain() == 0) {
            parseBlockMultiThread(&maps[id], &locks[id], block);
        } else {
            pool.spawnWg(&wg, parseBlockMultiThread, .{ &maps[id], &locks[id], block });
        }
    }
    wg.wait();

    // Merge maps
    for (1..maps.len) |mi| {
        const map: *BRCMap = &maps[mi];
        for (0..map.keys.len) |ki| {
            if (map.keys[ki] != null) {
                try maps[0].addOrMerge(map.keys[ki].?.get(), &map.values[ki].?);
            }
        }
        map.deinit();
    }
    defer maps[0].deinit();
    try printBrcMap(&maps[0]);
}

fn printBrcMap(map: *const BRCMap) !void {
    const rawbuf: []u8 = try map.allocator.alloc(u8, 1160_000);
    defer map.allocator.free(rawbuf);

    var buf: []u8 = rawbuf[0..];
    buf[0] = '{';
    buf = buf[1..];

    var rem: usize = map.count;

    for (0..map.keys.len) |i| {
        if (map.keys[i] != null) {
            if (rem < map.count) {
                buf[0] = ',';
                buf = buf[1..];
            }
            const val = map.values[i].?;
            const record = try std.fmt.bufPrint(buf, "{s}={d:.1}/{d:.1}/{d:.1}", .{
                map.keys[i].?.get(),
                val.minF(),
                val.meanF(),
                val.maxF(),
            });
            buf = buf[record.len..];
            rem -= 1;
        }
        if (rem == 0) break;
    }
    buf[0] = '}';
    buf = buf[1..];

    const stdout = std.io.getStdOut();
    _ = try stdout.write(rawbuf[0..(rawbuf.len - buf.len)]);
}

fn run() !void {
    const stderr = std.io.getStdErr().writer();
    const args = try std.process.argsAlloc(static_allocator);
    defer std.process.argsFree(static_allocator, args);
    const filepath = if (args.len == 2) args[1] else debugfilepath;

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

fn debug() !void {
    var len_u: u48 = 510;
    const len_a = std.mem.asBytes(&len_u);
    _ = &len_a;

    const stderr = std.io.getStdErr().writer();
    const endian: std.builtin.Endian = builtin.target.cpu.arch.endian();
    try std.fmt.format(stderr, "endianess: {s}", .{@tagName(endian)});

    // while (len_u <= 520) : (len_u += 1) {
    //     try std.fmt.format(stderr, "usize: {d} | array: ", .{len_u});
    //     for(0..len_a.len)|i|{
    //         if(i > 0) _ = try stderr.write(", ");
    //         try std.fmt.format(stderr, "[{d}] = {d:>3}",.{i,len_a[i]});
    //     }
    //     try stderr.writeByte('\n');
    // }
}

pub fn main() !void {
    try run();
}
