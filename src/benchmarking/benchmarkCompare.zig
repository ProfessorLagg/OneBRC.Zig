const builtin = @import("builtin");
const std = @import("std");

const sorted = @import("../sorted/sorted.zig");
const compare = sorted.compare;

const data = @import("data/data.zig");

pub const BenchmarkCompare = struct {
    const MapKey = @import("../parsing.zig").MapKey;

    var keys: []MapKey = undefined;
    var stdout: std.fs.File.Writer = undefined;
    fn print(comptime fmt: []const u8, args: anytype) void {
        std.fmt.format(stdout, fmt, args) catch {
            @panic("Could not print to stdout");
        };
    }
    fn noprint(comptime fmt: []const u8, args: anytype) void {
        _ = &fmt;
        _ = &args;
    }
    fn print_debug(comptime fmt: []const u8, args: anytype) void {
        const printFn = comptime switch (builtin.mode) {
            .ReleaseFast, .ReleaseSmall, .ReleaseSafe => noprint,
            .Debug => print,
        };
        printFn(fmt, args);
    }

    fn GSetup(allocator: std.mem.Allocator) !void {
        var lines = try data.allocReadCityNames(allocator);
        defer lines.deinit();

        keys = try allocator.alloc(MapKey, lines.items.len);
        for (0..lines.items.len) |i| {
            keys[i].set(lines.items[i]);
        }

        stdout = std.io.getStdOut().writer();
    }

    const BenchmarkFunction = (fn (a: *const MapKey, b: *const MapKey) sorted.CompareResult);
    const BenchmarkResult = struct {
        runCount: u64,
        sumNs: u64,

        pub inline fn getMeanNs(self: *const BenchmarkResult) f64 {
            const c: f64 = @floatFromInt(self.runCount);
            const s: f64 = @floatFromInt(self.sumNs);
            return s / c;
        }

        pub inline fn getRuntimeSeconds(self: *const BenchmarkResult) f64 {
            const c: f64 = std.time.ns_per_s;
            const s: f64 = @floatFromInt(self.sumNs);
            return s / c;
        }

        pub inline fn getOpsPerUnit(self: *const BenchmarkResult, unit: comptime_float) f64 {
            const ns: f64 = @floatFromInt(self.sumNs);
            const t: f64 = ns / @as(f64, unit);

            const ops: f64 = @floatFromInt(self.runCount);
            return ops / t;
        }
    };
    fn run_benchmark(comptime benchmark: BenchmarkFunction, comptime name: []const u8) void {
        const iter_count: usize = 1;

        var sum: i8 = 0;
        const start_time = std.time.nanoTimestamp();
        for (0..iter_count) |_| {
            for (0..keys.len) |i| {
                for (0..keys.len) |j| {
                    sum +%= @as(i8, @intFromEnum(benchmark(&keys[i], &keys[j])));
                }
            }
        }

        const end_time = std.time.nanoTimestamp();
        const ns: u64 = @intCast(end_time - start_time);

        const result = BenchmarkResult{ // NO FOLD
            .runCount = keys.len * keys.len * iter_count,
            .sumNs = ns,
        };
        print(name ++ "\truntime: {d:.3} s, mean: {d:.5} ns, {d:.0} op/us | check={d}\n", .{ result.getRuntimeSeconds(), result.getMeanNs(), result.getOpsPerUnit(std.time.ns_per_us), sum });
    }

    pub fn run() void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator: std.mem.Allocator = gpa.allocator();
        defer _ = gpa.deinit();

        GSetup(allocator) catch {
            @panic("Could not run Global Setup");
        };

        inline for (0..60) |_| {
            run_benchmark(MapKey.compare, "compare");
            print("\n", .{});
        }
    }
};
