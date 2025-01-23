const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const parsing = @import("parsing.zig");
const parallel = @import("parallel/parallel.zig");
const sorted = @import("sorted/sorted.zig");

pub const std_options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseSmall => .info,
        .ReleaseFast => .warn,
    },
};

// const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\simple.txt";
// const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\verysmall.txt";
// const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\small.txt";
// const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\medium.txt";
// const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\1GB.txt";
const debugpath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\large.txt";

pub fn main() !void {
    // TODO parse console args
    // try run();
    try run_debug();
    // try run_read();
    // run_benchmark();
}

fn run() !void {
    _ = try parsing.parse(debugpath[0..], true);
}
fn run_debug() !void {
    const stdout = std.io.getStdOut().writer();
    try std.fmt.format(stdout, "run_debug()\n", .{});
    var timer = try std.time.Timer.start();
    const parseResult: parsing.ParseResult = try parsing.parse(debugpath[0..], false);

    const ns: u64 = timer.read();
    const nsf: f64 = @floatFromInt(ns);
    const s: f64 = nsf / std.time.ns_per_s;
    const ns_per_line: f64 = nsf / @as(f64, @floatFromInt(parseResult.lineCount));

    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    const stat: std.fs.File.Stat = blk: {
        var buf: [4096]u8 = undefined;
        const abspath = try std.fs.cwd().realpath(debugpath, buf[0..]);
        var file = try std.fs.openFileAbsolute(abspath, comptime std.fs.File.OpenFlags{ //NOFOLD
            .mode = .read_only,
            .lock = .none,
            .lock_nonblocking = false,
            .allow_ctty = false,
        });
        defer file.close();
        const stat = try file.stat();
        break :blk stat;
    };

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(stat.size)) / s);
    try std.fmt.format(stdout, "\tparsed {d:.0} lines in {s} | {d:.2} ns/line | found {d} unique keys ({d:.2}%) | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, uniqueKeys, key_percent, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

fn run_read() !void {
    const stdout = std.io.getStdOut().writer();
    try std.fmt.format(stdout, "run_read()\n", .{});
    var timer = try std.time.Timer.start();
    const parseResult: parsing.ParseResult = try parsing.read(debugpath[0..]);

    const ns: u64 = timer.read();
    const nsf: f64 = @floatFromInt(ns);
    const s: f64 = nsf / std.time.ns_per_s;
    const ns_per_line: f64 = nsf / @as(f64, @floatFromInt(parseResult.lineCount));

    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    const stat: std.fs.File.Stat = blk: {
        var buf: [4096]u8 = undefined;
        const abspath = try std.fs.cwd().realpath(debugpath, buf[0..]);
        var file = try std.fs.openFileAbsolute(abspath, comptime std.fs.File.OpenFlags{ //NOFOLD
            .mode = .read_only,
            .lock = .none,
            .lock_nonblocking = false,
            .allow_ctty = false,
        });
        defer file.close();
        const stat = try file.stat();
        break :blk stat;
    };

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(stat.size)) / s);
    try std.fmt.format(stdout, "\tread {d:.0} lines in {any} | {d:.2} ns/line | found {d} unique keys ({d:.2}%) | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, uniqueKeys, key_percent, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

fn run_benchmark() void {
    const benchmarking = @import("benchmarking/benchmarking.zig");
    benchmarking.BenchmarkCompare.run();
}
