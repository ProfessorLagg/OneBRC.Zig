const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseSmall => .warn,
        .ReleaseFast => .warn,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .DelimReader, .level = .err },
        .{ .scope = .BRCMap, .level = .debug },
        .{ .scope = .Lines, .level = .err },
    },
};

// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.rev.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple2.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";

// following files has more than 1 instance of each key, and 41343 keys in total
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

const allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

inline fn ceilPowerOfTwo(comptime T: type, v: T) T {
    comptime {
        const ti: std.builtin.Type = @typeInfo(T);
        if (ti != .int or ti.int.signedness != .unsigned) @compileError("Expected unsigned integer, but found " + @typeName(T));
    }
    const isPowerOf2: bool = @popCount(v) == 1; // true if v is a power of 2 greater than 0
    const retMax: bool = v > (std.math.maxInt(T) / 2 + 1); // true if the function should return int max for input type
    const shiftBy = @bitSizeOf(T) - @clz(v - @intFromBool(isPowerOf2));
    const r0: T = (@as(T, 1) << @truncate(shiftBy)) * @as(T, @intFromBool(!retMax));
    const r1: T = @as(T, std.math.maxInt(T)) * @as(T, @intFromBool(retMax));
    return r0 + r1;
}

pub fn main() !void {
    // const stdout = std.io.getStdOut().writer();

    // var capacity: u8 = 0;
    // while (capacity < std.math.maxInt(u8)) : (capacity += 1) {
    //     const new_capacity: u8 = ceilPowerOfTwo(u8, capacity);
    //     std.fmt.format(stdout, "clz(capacity): {d}, capacity: {d}, new_capacity: {d}\n", .{ @clz(capacity), capacity, new_capacity }) catch unreachable;
    // }

    try bench_parse();
    //try bench_read();
    //try run();
}

pub fn bench_parse() !void {
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

pub fn bench_read() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;
    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    var parsed = try parser.read();
    const linecount = parser.linecount;
    const keycount = parsed.keys.items.len;
    const filesize: u64 = (try parser.file.stat()).size;
    parser.deinit();
    parsed.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = @intFromFloat(@as(f64, @floatFromInt(duration_ns)) / @as(f64, @floatFromInt(linecount)));

    const seconds_f: f64 = @as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_s);
    const bytes_per_sec_f: f64 = @as(f64, @floatFromInt(filesize)) / seconds_f;
    const bytes_per_sec: u64 = @intFromFloat(std.math.round(bytes_per_sec_f));
    try std.fmt.format(stdout, "\n==========\nRead {d} lines ({d} keys) in {} ({} /line) | {d:0.2}/s", .{
        linecount,
        keycount,
        std.fmt.fmtDuration(duration_ns),
        std.fmt.fmtDuration(ns_per_line),
        std.fmt.fmtIntSizeDec(bytes_per_sec),
    });
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
