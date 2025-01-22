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

// const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\verysmall.txt";
// const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\small.txt";
// const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\medium.txt";
const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\1GB.txt";
// const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\large.txt";

pub fn main() !void {
    // TODO parse console args

    // try run_debug();
    try run_read();
    try run_read();
    try run_read();
    try run_read();
    try run_read();
    try run_read();
    // run_benchmark();
}

fn run_debug() !void {
    var timer = try std.time.Timer.start();
    const parseResult: parsing.ParseResult = try parsing.parse(path[0..]);

    const ns: f64 = @floatFromInt(timer.read());
    const s: f64 = ns / std.time.ns_per_s;
    const ns_per_line: f64 = ns / @as(f64, @floatFromInt(parseResult.lineCount));

    // Turn this into a cli argument
    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    std.log.warn("read {d:.0} lines in {d:.2} s | {d:.2} ns/line | found {d} unique keys ({d:.2}%)", .{ parseResult.lineCount, s, ns_per_line, uniqueKeys, key_percent });
}

fn run_read() !void {
    var timer = try std.time.Timer.start();
    const parseResult: parsing.ParseResult = try parsing.read(path[0..]);

    const ns: f64 = @floatFromInt(timer.read());
    const s: f64 = ns / std.time.ns_per_s;
    const ns_per_line: f64 = ns / @as(f64, @floatFromInt(parseResult.lineCount));

    // Turn this into a cli argument
    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    std.log.warn("read {d:.0} lines in {d:.2} s | {d:.2} ns/line | found {d} unique keys ({d:.2}%)", .{ parseResult.lineCount, s, ns_per_line, uniqueKeys, key_percent });
}

fn run_benchmark() void {
    const benchmarking = @import("benchmarking/benchmarking.zig");
    benchmarking.BenchmarkCompare.run();
}
