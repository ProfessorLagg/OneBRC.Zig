const builtin = @import("builtin");
const std = @import("std");
const panic = std.debug.panic;
const assert = std.debug.assert;
const intrin = @import("intrinsics.zig");

fn sum_u64(samples: []const u64) u64 {
    var r: u64 = 0;
    // TODO Vectorize this
    for (samples) |s| r +%= s;
    return r;
}

comptime {
    if (builtin.target.cpu.arch != .x86_64) @compileError("This only works on x86_64");
}

pub const BenchmarkResult = struct {
    samples: []const u64,

    pub fn init(samples: []const u64) BenchmarkResult {
        return BenchmarkResult{ .samples = samples };
    }
    pub fn deinit(self: *BenchmarkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
    }

    /// The total number of times the function was run
    pub inline fn getCount(self: BenchmarkResult) u64 {
        return self.samples.len;
    }
    /// The total nanoseconds for all runs
    pub fn getSum(self: BenchmarkResult) u64 {
        return sum_u64(self.samples[0..]);
    }
    /// The mean of all runs
    pub fn getMean(self: BenchmarkResult) f64 {
        const count_f: f64 = @floatFromInt(self.getCount());
        const ns_f: f64 = @floatFromInt(sum_u64(self.samples));
        return ns_f / count_f;
    }
    /// returns the statistical variance across all runs
    pub fn getVariance(self: BenchmarkResult) f64 {
        const mean: f64 = self.getMean();
        var sum_of_squares: f64 = 0.0;
        for (self.samples) |sample| {
            const dmean: f64 = @as(f64, @floatFromInt(sample)) - mean;
            sum_of_squares += dmean * dmean;
        }
        const variance: f64 = sum_of_squares / @as(f64, @floatFromInt(self.samples.len - 1));
        return variance;
    }
    /// returns the standard deviation accross all runs
    pub fn getStandardDeviation(self: BenchmarkResult) f64 {
        return @sqrt(self.getVariance());
    }

    pub fn format(self: BenchmarkResult, writer: *std.io.Writer) std.io.Writer.Error!void {
        return writer.print("count: {d}, time: {D}, mean: {D}/run, standard deviation: {D}", .{
            self.getCount(),
            self.getSum(),
            @as(u64, @intFromFloat(@round(self.getMean()))),
            @as(u64, @intFromFloat(@round(self.getStandardDeviation()))),
        });
    }
};
pub const BenchmarkOptions = struct {
    /// Number of times the function is run per batch
    /// The function will be run `batchSize * minBatches` times
    batchSize: comptime_int = 1,
    /// The minimum number of batches to run.
    /// The function will be run atleast `batchSize * minBatches` times
    minBatches: comptime_int = 1,
    /// The minimum total time to benchmark for
    minNs: comptime_int = std.time.ns_per_s,
};

pub fn runBenchmark(
    /// Type of context
    comptime T: type,
    /// Run Options
    comptime opt: BenchmarkOptions,
    /// Function to run
    comptime run: fn (T) void,
    allocator: std.mem.Allocator,
    context: T,
) BenchmarkResult {
    const Ti: std.builtin.Type = comptime @typeInfo(T);

    var count: u64 = 0;
    var time: u64 = 0;
    var batchTimes = std.ArrayList(u64){};
    defer batchTimes.deinit(allocator);

    var batch: u64 = 0;
    // TODO Build custom timer from RDTSC
    var timer = std.time.Timer.start() catch |err| panic("{any}{any}", .{ err, @errorReturnTrace() });
    while (time < opt.minNs or batch < opt.minBatches) : (batch += 1) {
        if (comptime (Ti == .@"struct" and std.meta.hasMethod(T, "batchSetup"))) context.batchSetup();

        asm volatile ("mfence");
        timer.reset();
        inline for (0..opt.batchSize) |_| {
            @setRuntimeSafety(false);
            asm volatile ("mfence");
            @call(.always_inline, run, .{context});
            asm volatile ("mfence");
        }
        const timeNs: u64 = timer.read();
        if (comptime (Ti == .@"struct" and std.meta.hasMethod(T, "batchCleanup"))) context.batchCleanup();
        count += opt.batchSize;
        time += timeNs;
        batchTimes.append(allocator, timeNs / opt.batchSize) catch |err| panic("{any}{any}", .{ err, @errorReturnTrace() });
    }

    return BenchmarkResult.init(batchTimes.toOwnedSlice(allocator) catch |err| panic("{any}{any}", .{ err, @errorReturnTrace() }));
}

pub const LineGenerator = struct {
    const citiesRaw = @embedFile("cities.txt");
    fn getCities(allocator: std.mem.Allocator) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .{};
        var iter = std.mem.splitScalar(u8, citiesRaw, '\n');
        while (iter.next()) |line| {
            const trim = std.mem.trim(u8, line, " \t\n\r");
            if (trim.len < 2) continue;
            try list.append(allocator, trim);
        }
        return try list.toOwnedSlice(allocator);
    }

    prng: std.Random.DefaultPrng,
    valid_keys: []const []const u8,
    rem_keys: std.ArrayList(usize) = .{},
    pub fn initEx(allocator: std.mem.Allocator, prng: std.Random.DefaultPrng) !LineGenerator {
        const cities = try getCities(allocator);
        const rem_keys = try std.ArrayList(usize).initCapacity(allocator, cities.len);
        return .{
            .prng = prng,
            .valid_keys = cities,
            .rem_keys = rem_keys,
        };
    }
    pub fn initSeed(allocator: std.mem.Allocator, seed: u64) !LineGenerator {
        const prng = std.Random.DefaultPrng.init(seed);
        return try initEx(allocator, prng);
    }
    pub fn init(allocator: std.mem.Allocator) !LineGenerator {
        const seed: u64 = intrin.rdseed64();
        return try initSeed(allocator, seed);
    }
    pub fn deinit(self: *LineGenerator, allocator: std.mem.Allocator) void {
        allocator.free(self.valid_keys);
        self.rem_keys.deinit(allocator);
    }

    pub fn nextKeystr(self: *LineGenerator) []const u8 {
        if (self.rem_keys.items.len == 0) {
            for (0..self.valid_keys.len) |idx| self.rem_keys.appendAssumeCapacity(idx);
            self.prng.random().shuffle(usize, self.rem_keys.items);
        }
        const idx = self.rem_keys.pop().?;
        return self.valid_keys[idx];
    }
    pub fn nextValstr(self: *LineGenerator) [5:0]u8 {
        var rsp: [5:0]u8 = undefined;
        @memset(rsp[0..], 0);

        var idx: u8 = 0;
        const rand = self.prng.random();
        if (rand.boolean()) { // Generate sign
            rsp[idx] = '-';
            idx += 1;
        }

        // Generate first numeral
        rsp[idx] = rand.intRangeAtMost(u8, '0', '9');
        idx += 1;

        if (rand.boolean()) { // Generate optional second numeral
            rsp[idx] = rand.intRangeAtMost(u8, '0', '9');
            idx += 1;
        }

        // Generate decimal
        rsp[idx] = '.';
        idx += 1;
        rsp[idx] = rand.intRangeAtMost(u8, '0', '9');

        return rsp;
    }
    pub fn nextAlloc(self: *LineGenerator, allocator: std.mem.Allocator) ![]const u8 {
        var buf: [105]u8 = undefined;
        const out = self.next(&buf);
        const rsp = try allocator.alloc(u8, out.len);
        @memcpy(rsp[0..], out);
        return rsp;
    }
    pub fn next(self: *LineGenerator, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= 105);
        var i: usize = 0;
        const key = self.nextKeystr();
        for (key) |c| {
            buf[i] = c;
            i += 1;
        }
        buf[i] = ';';
        i += 1;
        const val = self.nextValstr();
        for (val) |c| {
            if (c == 0) break;
            buf[i] = c;
            i += 1;
        }

        return buf[0..i];
    }
};
