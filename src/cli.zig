const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const parsing = @import("parsing.zig");
const parallel = @import("parallel/parallel.zig");
const sorted = @import("sorted/sorted.zig");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseSmall => .info,
        .ReleaseFast => .warn,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .SortedArrayMap, .level = .err },
    },
};

// const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\simple.txt";
// const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\verysmall.txt";
// const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\small.txt";
// const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\medium.txt";
// const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\1GB.txt";
const debugfilepath = "C:\\CodeProjects\\1BillionRowChallenge\\data\\large.txt";

pub fn main() !void {
    // TODO parse console args
    // try run();
    try run_debug();
    // try run_read();
    // run_benchmark();
}

fn run() !void {
    _ = try parsing.parse(debugfilepath[0..], true);
}
fn run_debug() !void {
    std.log.debug("run_debug()", .{});
    const start_time = std.time.nanoTimestamp();
    const parseResult: parsing.ParseResult = try parsing.parse(debugfilepath[0..], false);
    const end_time = std.time.nanoTimestamp();

    const ns: u64 = @intCast(end_time - start_time);
    const nsf: f64 = @floatFromInt(ns);
    const s: f64 = nsf / std.time.ns_per_s;
    const ns_per_line: f64 = nsf / @as(f64, @floatFromInt(parseResult.lineCount));

    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    const stat: std.fs.File.Stat = blk: {
        var buf: [4096]u8 = undefined;
        const abspath = try std.fs.cwd().realpath(debugfilepath, buf[0..]);
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
    std.log.warn("parsed {d:.0} lines in {any} | {d:.2} ns/line | found {d} unique keys ({d:.2}%) | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, uniqueKeys, key_percent, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

fn run_read() !void {
    std.log.debug("run_read()", .{});
    var timer = try std.time.Timer.start();
    const parseResult: parsing.ParseResult = try parsing.read(debugfilepath[0..]);

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
        const abspath = try std.fs.cwd().realpath(debugfilepath, buf[0..]);
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
    std.log.warn("read {d:.0} lines in {any} | {d:.2} ns/line | found {d} unique keys ({d:.2}%) | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, uniqueKeys, key_percent, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

fn run_benchmark() void {
    std.log.debug("run_benchmark()", .{});
    const benchmarking = @import("benchmarking/benchmarking.zig");
    benchmarking.BenchmarkCompare.run();
}

const ContainsIterator = struct {
    strings: []const []const u8,
    needle: []const u8,
    index: usize = 0,
    fn next(self: *ContainsIterator) ?[]const u8 {
        const index = self.index;
        for (self.strings[index..]) |string| {
            self.index += 1;
            if (std.mem.indexOf(u8, string, self.needle)) |_| {
                return string;
            }
        }
        return null;
    }
};

test "custom iterator" {
    var iter = ContainsIterator{
        .strings = &[_][]const u8{ "one", "two", "three" },
        .needle = "e",
    };

    try std.testing.expectEqual("one", iter.next().?);
    try std.testing.expectEqual("three", iter.next().?);
    try std.testing.expectEqual(null, iter.next());
}
