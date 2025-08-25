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
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const allocator: std.mem.Allocator = b: {
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

pub fn main() !void {
    const blocksize: comptime_int = 4096;
    const BlockReader: type = lib.BlockReader(blocksize);
    var reader: BlockReader = try BlockReader.init(debugfilepath);
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    var i: usize = 0;
    var map = try BRCMap.init(allocator);
    defer map.deinit();
    var totalLineCount: usize = 0;
    while (reader.next()) |block| : (i += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        const linecount = parseBlock(&map, block);
        totalLineCount += linecount;
        try std.fmt.format(stdout, "Block {d} had {d} lines\n", .{ i, linecount });
    }

    try std.fmt.format(stdout, "found {d} keys in {d} lines\n", .{ map.count, totalLineCount });
}
