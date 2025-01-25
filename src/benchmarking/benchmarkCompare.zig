const builtin = @import("builtin");
const std = @import("std");

const sorted = @import("../sorted/sorted.zig");
const compare = sorted.compare;

const data = @import("data/data.zig");

pub const BenchmarkCompare = struct {
    const MapKey = @import("../parsing.zig").MapKey;

    var keys: []MapKey = undefined;
    var stdout: std.fs.File.Writer = undefined;
    inline fn print(comptime fmt: []const u8, args: anytype) void {
        std.fmt.format(stdout, fmt, args) catch {
            @panic("Could not print to stdout");
        };
    }
    inline fn prints(comptime fmt: []const u8) void {
        print(fmt, .{});
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
        var lines = try data.readCityNames(allocator);
        defer lines.deinit();

        keys = try allocator.alloc(MapKey, lines.items.len);
        for (0..lines.items.len) |i| {
            keys[i].set(lines.items[i]);
        }

        stdout = std.io.getStdOut().writer();
    }

    const BenchmarkFunction = (fn (a: *const MapKey, b: *const MapKey) sorted.CompareResult);
    const BenchmarkResult = struct {
        ns: u64 = 0,
        count: u64 = 0,

        pub inline fn getMeanNs(self: *const BenchmarkResult) f64 {
            const c: f64 = @floatFromInt(self.count);
            const s: f64 = @floatFromInt(self.ns);
            return s / c;
        }

        pub inline fn getRuntimeSeconds(self: *const BenchmarkResult) f64 {
            const c: f64 = std.time.ns_per_s;
            const s: f64 = @floatFromInt(self.ns);
            return s / c;
        }

        pub inline fn getOpsPerUnit(self: *const BenchmarkResult, unit: comptime_float) f64 {
            const ns: f64 = @floatFromInt(self.ns);
            const t: f64 = ns / @as(f64, unit);

            const ops: f64 = @floatFromInt(self.count);
            return ops / t;
        }

        pub inline fn add(self: *BenchmarkResult, ns: u64, count: u64) void {
            self.count += count;
            self.ns += ns;
        }
        pub inline fn addr(self: *BenchmarkResult, other: *const BenchmarkResult) void {
            self.add(other.ns, other.count);
        }
    };

    const validateLog = std.log.scoped(.ValidateBenchmark);

    fn validate_benchmark(comptime benchmarkA: BenchmarkFunction, comptime benchmarkB: BenchmarkFunction) void {
        for (0..keys.len) |i| {
            for (0..keys.len) |j| {
                const resultA = benchmarkA(&keys[i], &keys[j]);
                const resultB = benchmarkB(&keys[i], &keys[j]);
                const vA: u8 = @abs(@intFromEnum(resultA));
                const vB: u8 = @abs(@intFromEnum(resultB));
                if (vA != vB) {
                    validateLog.err("Different benchmark return values! A: {s}, B: {s}", .{ @tagName(resultA), @tagName(resultB) });
                    @panic("Different benchmark return values!");
                } else if (resultA != resultB) {
                    validateLog.info("Different benchmark return values! A: {s}, B: {s}", .{ @tagName(resultA), @tagName(resultB) });
                }
            }
        }
    }
    fn run_benchmark(comptime benchmark: BenchmarkFunction, comptime name: []const u8) BenchmarkResult {
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
            .count = keys.len * keys.len * iter_count,
            .ns = ns,
        };
        print(name ++ "\truntime: {d:.3} s, mean: {d:.5} ns, {d:.0} op/us | check={d}\n", .{ result.getRuntimeSeconds(), result.getMeanNs(), result.getOpsPerUnit(std.time.ns_per_us), sum });
        return result;
    }

    pub fn run() void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator: std.mem.Allocator = gpa.allocator();
        defer _ = gpa.deinit();

        GSetup(allocator) catch {
            @panic("Could not run Global Setup");
        };

        const aName = comptime "base";
        const bName = comptime "impr";
        const aFunc = comptime MapKey.compare;
        const bFunc = comptime MapKey.compare2;

        validate_benchmark(aFunc, bFunc);
        inline for (0..64) |_| {
            const a = run_benchmark(aFunc, aName);
            const b = run_benchmark(bFunc, bName);

            const nameOfFastest = switch (a.ns < b.ns) {
                true => aName,
                false => bName,
            };
            print("best: {s} \n\n", .{nameOfFastest});
        }
    }
};
