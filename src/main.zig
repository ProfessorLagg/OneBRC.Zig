const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

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
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_trail.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const static_allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

var gpa: std.mem.Allocator = undefined;
var io: Io = undefined;

fn bench(filepath: []const u8) !void {
    lib.stderrPrint("Parsing file: {s}\n", .{filepath});

    const fileSize = (try (try std.fs.cwd().openFile(filepath, .{})).stat()).size;
    var timer = try std.time.Timer.start();
    try Parser.DefaultParser.parseFile(gpa, filepath);
    const ns = timer.read();
    const ns_f: f64 = @floatFromInt(ns);
    const s_f: f64 = ns_f / @as(f64, @floatFromInt(std.time.ns_per_s));
    const fileSize_f: f64 = @floatFromInt(fileSize);
    const perf_f: f64 = @round(fileSize_f / s_f);
    const perf: u64 = @intFromFloat(perf_f);

    lib.stderrPrint("\n\nparsed {Bi} in {D} at {Bi}/s\n", .{
        fileSize,
        ns,
        perf,
    });
}
pub fn main(init: std.process.Init.Minimal) !void {
    gpa = static_allocator;

    var threaded: std.Io.Threaded = .init(gpa, std.Io.Threaded.InitOptions{
        .argv0 = .init(init.args),
        .environ = init.environ,
        .async_limit = .limited(try std.Thread.getCpuCount() - 1),
        .concurrent_limit = .unlimited,
    });
    io = threaded.io();

    // const args = try std.process.argsAlloc(gpa);
    // defer std.process.argsFree(gpa, args);
    const pargs: lib.Args2 = try .init(init.args, gpa);
    const filepath = if (pargs.args.len > 0) pargs.args[0] else debugfilepath;

    //try clearFileCache();
    // try Parser.DefaultParser.parseFile(static_allocator, filepath);
    //try dbg();
    //try benchmark_parseLine();
    // try benchmark_findKeyIndex();
    //try baseline.read(filepath);
    //try bench(filepath);
    try debug(filepath);
}

fn debug(filepath: []const u8) !void {
    const bufsizes = [_]comptime_int{
        4 * 1024, // page
        8 * 1024,
        16 * 1024,
        32 * 1024,
        64 * 1024,
        128 * 1024,
        256 * 1024,
        512 * 1024, // L1
        1 * 1024 * 1024,
        2 * 1024 * 1024,
        4 * 1024 * 1024, // L2
        8 * 1024 * 1024,
        16 * 1024 * 1024,
        32 * 1024 * 1024, // L3
    };
    const runcount: comptime_int = 10;

    var timer: lib.Timer_awake = .start();
    inline for (bufsizes) |bufsize| {
        var runtime_ns: u64 = std.math.maxInt(u64);
        var newLines: usize = 0;
        inline for (0..runcount) |_| {
            timer.reset();
            newLines = try debugInner(bufsize, filepath);
            runtime_ns = @min(runtime_ns, @as(u64, @intCast(@abs(timer.read()))));
        }

        lib.stdoutPrint("Found {d} newlines in {d:>5} ms using bufsize {Bi}\n", .{ newLines, runtime_ns / 1000, bufsize });
    }
}

fn debugInner(comptime bufsize: comptime_int, filepath: []const u8) !usize {
    const buffer: []u8 = try gpa.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(4096), bufsize);
    defer gpa.free(buffer);

    var file = try Io.Dir.cwd().openFile(io, filepath, .{});
    defer file.close(io);

    var readlen: usize = file.readPositionalAll(io, buffer, 0) catch unreachable;
    var newLines: usize = 0;
    while (readlen > 0) {
        newLines += countChar('\n', buffer.ptr, readlen);
        readlen = file.readPositionalAll(io, buffer, 0) catch unreachable;
    }
    return newLines;
}
fn countChar(comptime c: u8, ptr: [*]const u8, len: usize) usize {
    const veclen: comptime_int = std.simd.suggestVectorLength(u8) orelse 256 / 8;
    const charvec: @Vector(veclen, u8) = comptime @splat(c);
    var r: usize = 0;

    const vecend: usize = (len / veclen) * veclen;
    var i: usize = 0;
    while (i < vecend) : (i += veclen) {
        const vec = std.mem.bytesAsValue(@Vector(veclen, u8), ptr[i .. i + veclen]);
        const eql: @Vector(veclen, u8) = @intFromBool(vec.* == charvec);
        r += @reduce(.Add, eql);
    }

    while (i < len) : (i += 1) r += @intFromBool(ptr[i] == c);

    return r;
}
noinline fn countChar2(comptime c: u8, ptr: [*]const u8, len: usize) usize {
    const asmstr = std.fmt.comptimePrint(
        "xor %[ret], %[ret]\nxor %rbx, %rbx\n.countChar_loopstart_{0d}:\ncmpb ${0d}, -1(%[ptr], %[len])\nsete %bl\nadd %rbx, %[ret]\nloop .countChar_loopstart_{0d}",
        .{c},
    );
    return asm volatile (asmstr
        : [ret] "={rax}" (-> usize),
        : [ptr] "{rsi}" (ptr),
          [len] "{rcx}" (len),
        : .{ .rbx = true });
}

fn countChar1(comptime c: u8, ptr: [*]const u8, len: usize) usize {
    var r: usize = 0;
    for (0..len) |i| {
        r += @intFromBool(ptr[i] == c);
    }
    return r;
}

fn clearFileCache() !void {
    const stderr = lib.getStderr();
    defer stderr.flush() catch unreachable;
    switch (builtin.target.os.tag) {
        .windows => {
            var memstat: lib.c.MEMORYSTATUSEX = std.mem.zeroes(lib.c.MEMORYSTATUSEX);
            memstat.dwLength = @sizeOf(lib.c.MEMORYSTATUSEX);
            if (lib.c.GlobalMemoryStatusEx(&memstat) == 0) {
                const err = std.os.windows.GetLastError();
                return std.os.windows.unexpectedError(err);
            }

            const avail: usize = @intCast(memstat.ullAvailPhys);
            try stderr.print("Found {Bi} available physical memory\n", .{avail});
            try stderr.flush();
            const alloc = try gpa.alloc(u8, avail);
            @memset(alloc[0..], '@');
            gpa.free(alloc);
        },

        else => @compileError("Not yet implemented"),
    }
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
    const runCount: comptime_int = 2;
    std.debug.assert(runCount > 0);

    // Setup printing
    const stderr: *std.io.Writer = lib.getStderr();
    defer stderr.flush() catch unreachable;

    // Generate Lines
    stderr.print("Generating lines...\n", .{}) catch unreachable;
    stderr.flush() catch unreachable;
    const lines: []const []const u8 = try LineGenerator.getAll(gpa);
    defer {
        for (0..lines.len) |i| gpa.free(lines[i]);
        gpa.free(lines);
    }

    // Setup Running
    const runs: []u64 = try gpa.alloc(u64, runCount);
    defer gpa.free(runs);
    var key: []const u8 = undefined;
    var val: i16 = undefined;
    var keysum: usize = 0;
    var valsum: i16 = 0;
    // Run
    stderr.print("Running...\n", .{}) catch unreachable;
    stderr.flush() catch unreachable;
    for (0..runCount) |runId| {
        stderr.print("\t{d} / {d}\n", .{ runId + 1, runCount }) catch unreachable;
        stderr.flush() catch unreachable;
        runs[runId] = 0;
        for (lines) |line| {
            const start: u64 = intrin.rdtsc_fenced();
            @call(.never_inline, Parser.parseLine, .{ line, &key, &val });
            const end: u64 = intrin.rdtsc_fenced();
            runs[runId] += end - start;

            keysum +%= key.len;
            valsum +%= val;
        }
        stderr.print("\x1b[2K\r{d};{d}\x1b[2K\r", .{ keysum, valsum }) catch unreachable;
        stderr.flush() catch unreachable;
    }

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
    const med: f64 = blk: {
        const a: f64 = @floatFromInt(runs[runs.len / 2]);
        if (runs.len % 2 == 0) break :blk a;
        const b: f64 = @floatFromInt(runs[(runs.len / 2) + 1]);
        break :blk ((a + b) / 2.0);
    };

    //b: {
    //    const aidx: usize = runCount / 2;
    //    const bidx: usize = aidx + @intFromBool(runs.len % 2 == 0);
    //    const s: f64 = @floatFromInt(runs[aidx] + runs[bidx]);
    //    break :b (s / 2.0);
    //};

    const minl: f64 = @as(f64, @floatFromInt(min)) / @as(f64, @floatFromInt(lines.len));
    const maxl: f64 = @as(f64, @floatFromInt(max)) / @as(f64, @floatFromInt(lines.len));
    const avgl: f64 = avg / @as(f64, @floatFromInt(lines.len));
    const medl: f64 = med / @as(f64, @floatFromInt(lines.len));

    // Print output
    stderr.print("Results\n\tmin: {d} | {d}\n\tmax: {d} | {d}\n\tavg: {d} | {d}\n\tmed: {d} | {d}\n", .{
        min,
        minl,
        max,
        maxl,
        avg,
        avgl,
        med,
        medl,
    }) catch unreachable;
}
