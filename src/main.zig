const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const baseline = @import("baseline.zig");
const Parser = @import("parser.zig");

// pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
//     std.log.err("{s}{any}", .{ msg, trace });
//     std.process.exit(1);
// }

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

fn bench(filepath: []const u8) !void {
    const stderr = lib.getStderr();
    defer stderr.flush() catch unreachable;

    try stderr.print("Parsing file: {s}\n", .{filepath});
    try stderr.flush();

    const fileSize = (try (try std.fs.cwd().openFile(filepath, .{})).stat()).size;
    var timer = try std.time.Timer.start();
    try Parser.DefaultParser.parseFilePath(static_allocator, filepath);
    const ns = timer.read();
    const ns_f: f64 = @floatFromInt(ns);
    const s_f: f64 = ns_f / @as(f64, @floatFromInt(std.time.ns_per_s));
    const fileSize_f: f64 = @floatFromInt(fileSize);
    const perf_f: f64 = @round(fileSize_f / s_f);
    const perf: u64 = @intFromFloat(perf_f);

    try stderr.print("\n\nparsed {Bi} in {D} at {Bi}/s\n", .{
        fileSize,
        ns,
        perf,
    });
}
pub fn main() !void {
    const args = try std.process.argsAlloc(static_allocator);
    defer std.process.argsFree(static_allocator, args);
    const filepath = if (args.len == 2) args[1] else debugfilepath;

    //try Parser.DefaultParser.parseFile(static_allocator, filepath);
    //try dbg();
    try benchmark_parseLine();
    //try baseline.read(filepath);
    // try bench(filepath);
    _ = &filepath;
}

fn dbg() !void {
    const CpuId = lib.intrinsics.CpuId;
    const leaf0 = CpuId.Leaf0.get();
    std.debug.print("max leaf: {d} (0x{d:0>8}) | vendor: \"{s}\"\n", .{ leaf0.maxLeaf, leaf0.maxLeaf, leaf0.vendorId });

    // const leaf15 = CpuId.Leaf15.get();
    const leaf13 = CpuId.cpuid(0x13);
    const leaf15 = CpuId.cpuid(0x15);
    const leaf16 = CpuId.cpuid(0x16);
    std.debug.print("leaf13: {}\n", .{leaf13});
    std.debug.print("leaf15: {}\n", .{leaf15});
    std.debug.print("leaf16: {}\n", .{leaf16});
}

fn benchmark_parseLine() !void {
    std.debug.print("Benchmark(Parser.parseLine)\n", .{});

    // Imports
    const intrin = lib.intrinsics;
    const LineGenerator = lib.benchmarking.LineGenerator;

    // Settings
    const runCount: comptime_int = 20;
    std.debug.assert(runCount > 0);

    // Generate Lines
    std.debug.print("Generating lines...\n", .{});
    const lines: []const []const u8 = try LineGenerator.getAll(static_allocator);
    defer {
        for (0..lines.len) |i| static_allocator.free(lines[i]);
        static_allocator.free(lines);
    }

    // Setup Running
    const runs: []u64 = try static_allocator.alloc(u64, runCount);
    defer static_allocator.free(runs);
    var key: []const u8 = undefined;
    var val: i16 = undefined;

    // Run
    std.debug.print("Running...", .{});
    for (0..runCount) |runId| {
        std.debug.print("\rRunning {d} / {d}", .{ runId + 1, runCount });
        runs[runId] = 0;
        for (lines) |line| {
            const start: u64 = intrin.rdtsc_fenced();
            @call(.always_inline, Parser.parseLine, .{ line, &key, &val });
            const end: u64 = intrin.rdtsc_fenced();
            runs[runId] += end - start;
        }
    }
    std.debug.print("\n", .{});

    // Generate output
    std.mem.sort(u64, runs, {}, std.sort.asc(u64));
    var sum: u64 = 0;
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = std.math.minInt(u64);
    for (runs) |t| {
        sum += t;
        min = @min(min, t);
        max = @max(max, t);
    }

    const avg: f64 = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(runs.len));
    const med: f64 = b: {
        const aidx: usize = runCount / 2;
        const bidx: usize = aidx + @intFromBool(runs.len % 2 == 0);
        const s: f64 = @floatFromInt(runs[aidx] + runs[bidx]);
        break :b (s / 2.0);
    };

    const minl: f64 = @as(f64, @floatFromInt(min)) / @as(f64, @floatFromInt(lines.len));
    const maxl: f64 = @as(f64, @floatFromInt(max)) / @as(f64, @floatFromInt(lines.len));
    const avgl: f64 = avg / @as(f64, @floatFromInt(lines.len));
    const medl: f64 = med / @as(f64, @floatFromInt(lines.len));

    // Print output
    std.debug.print("Results\n\tmin: {d} | {d}\n\tmax: {d} | {d}\n\tavg: {d} | {d}\n\tmed: {d} | {d}\n", .{
        min,
        minl,
        max,
        maxl,
        avg,
        avgl,
        med,
        medl,
    });
}
