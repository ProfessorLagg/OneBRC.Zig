const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseSmall => .warn,
        .ReleaseFast => .warn,
    },
};

// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.rev.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple2.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";

// following files has more than 1 instance of each key, and 41343 keys in total
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

const allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

pub fn main() !void {
    try bench();
    //try run();
}

pub fn bench() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;
    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    var parsed = try parser.parse();
    const linecount = parser.linecount;
    const keycount = parsed.keys.items.len;
    parser.deinit();
    parsed.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = duration_ns / linecount;
    try std.fmt.format(stdout, "\n==========\nParsed {d} lines | {d} keys | in {} ({} /line)", .{ linecount, keycount, std.fmt.fmtDuration(duration_ns), std.fmt.fmtDuration(ns_per_line) });
}

pub fn run() !void {
    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    defer parser.deinit();
    var parsed = try parser.parse();
    defer parsed.deinit();

    var iter = parsed.iterator();
    const stdout = std.io.getStdOut().writer();
    while (iter.next()) |kvp| {
        const valflt: f64 = kvp.val.mean() / 10.0;
        try std.fmt.format(stdout, "{s};{d:.1}\n", .{ kvp.key, valflt });
    }
}
