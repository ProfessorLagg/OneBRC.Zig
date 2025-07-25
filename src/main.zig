const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const ut = lib.utils;
const ParseResult = lib.BRCParser.BRCParseResult;

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .err,
        .ReleaseSafe => .err,
        .ReleaseSmall => .err,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .DelimReader, .level = .err },
        .{ .scope = .BRCMap, .level = .err },
        .{ .scope = .Lines, .level = .err },
    },
};

// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.rev.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple2.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";

// following files has more than 1 instance of each key, and 41343 keys in total
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

const allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

pub fn main() !void {
    defer lib.utils.debug.flush();
    // try temp();
    try bench_parse();
    // try bench_read();
    //try run();
}

fn temp() !void {
    ut.debug.print("{d: <6.3}\n{d: <6.3}", .{
        std.fmt.fmtDuration(1230 * std.time.ns_per_ms),
        std.fmt.fmtDuration(1234 * std.time.ns_per_ms),
    });
}

pub fn bench_parse() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;

    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    var result: ParseResult = try parser.parse();

    const filesize: u64 = (try parser.file.stat()).size;
    parser.deinit();

    const linecount = result.linecount;
    const keycount = result.entries.len;
    result.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = duration_ns / linecount;

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(filesize)) / (@as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_s)));
    const threadTagStr = comptime switch (builtin.single_threaded) {
        true => "Single Thread",
        false => "Multi Thread ",
    };
    try std.fmt.format(stdout, "{s} | Parsed {d} lines | {d} keys | in {d:.3} ({d:.3}/line | {d:.3}/s)", .{
        threadTagStr,
        linecount,
        keycount,
        std.fmt.fmtDuration(duration_ns),
        std.fmt.fmtDuration(ns_per_line),
        std.fmt.fmtIntSizeBin(bytes_per_second),
    });
}

pub fn bench_read() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;

    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    var result: ParseResult = try parser.read();

    const filesize: u64 = (try parser.file.stat()).size;
    parser.deinit();

    const linecount = result.linecount;
    const keycount = result.entries.len;
    result.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = duration_ns / linecount;

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(filesize)) / (@as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_s)));
    const threadTagStr = comptime switch (builtin.single_threaded) {
        true => "Single Thread",
        false => "Multi Thread ",
    };
    try std.fmt.format(stdout, "{s} | Parsed {d} lines | {d} keys | in {d:.3} ({d:.3}/line | {d:.3}/s)", .{
        threadTagStr,
        linecount,
        keycount,
        std.fmt.fmtDuration(duration_ns),
        std.fmt.fmtDuration(ns_per_line),
        std.fmt.fmtIntSizeBin(bytes_per_second),
    });
}

pub fn run() !void {
    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    defer parser.deinit();
    var parsed = try parser.parse();
    defer parsed.deinit();

    const stdout = std.io.getStdOut().writer();
    var bufwri = std.io.bufferedWriter(stdout);
    const writer = bufwri.writer();
    writer.writeByte('{') catch unreachable;
    var i: usize = parsed.entries.len;
    while (i > 1) {
        i -= 1;
        const final = parsed.entries[i].val.finalize();
        std.fmt.format(writer, "{s}={d:.1}/{d:.1}/{d:.1}, ", .{ parsed.entries[i].key, final.min, final.mean, final.max }) catch unreachable;
    }
    i -= 1;
    const final = parsed.entries[i].val.finalize();
    std.fmt.format(writer, "{s}={d:.1}/{d:.1}/{d:.1}", .{ parsed.entries[i].key, final.min, final.mean, final.max }) catch unreachable;
    writer.writeByte('}') catch unreachable;
    bufwri.flush() catch unreachable;
}
