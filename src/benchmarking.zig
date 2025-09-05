const builtin = @import("builtin");
const std = @import("std");
const panic = std.debug.panic;
const assert = std.debug.assert;

fn sum_u64(samples: []const u64) u64 {
    var r: u64 = 0;
    // TODO Vectorize this
    for (samples) |s| r +%= s;
    return r;
}

comptime {
    if (builtin.target.cpu.arch != .x86_64) @compileError("This only works on x86_64");
}

/// Performs a serializing operation on all load-from-memory and store-to-memory instructions that were issued prior the MFENCE instruction
fn mfence() void {
    asm volatile ("mfence");
}

/// Performs a serializing operation on all load-from-memory instructions that were issued prior the LFENCE instruction
fn lfence() void {
    asm volatile ("lfence");
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
