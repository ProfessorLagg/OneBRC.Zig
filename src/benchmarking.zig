const builtin = @import("builtin");
const std = @import("std");

const sorted = @import("sorted/sorted.zig");
const compare = sorted.compare;

const cityNames = @embedFile("data/worldcities.txt");
fn allocReadCityNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(allocator);

    var split_iter = std.mem.split(u8, cityNames[0..], "\n");
    var line: ?[]const u8 = split_iter.first();
    while (line != null) : (line = split_iter.next()) {
        if (line == null) {
            break;
        }
        try result.append(line.?);
    }

    return result;
}

pub const BenchmarkCompare = struct {
    const MapKey = @import("parsing.zig").MapKey;

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
        var lines = try allocReadCityNames(allocator);
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
    };
    fn run_benchmark(comptime benchmark: BenchmarkFunction, comptime name: []const u8) void {
        const iter_count: usize = 60;

        var sum: i8 = 0;
        const start_time = std.time.nanoTimestamp();
        for (0..iter_count) |_| {
            for (0..keys.len) |i| {
                for (0..keys.len) |j| {
                    sum += @as(i8, @intFromEnum(benchmark(&keys[i], &keys[j])));
                }
            }
        }
        const end_time = std.time.nanoTimestamp();
        const ns: u64 = @intCast(end_time - start_time);
        const result = BenchmarkResult{ // NO FOLD
            .runCount = keys.len * keys.len * iter_count,
            .sumNs = ns,
        };
        print(name ++ ": runtime: {d:.2} s, mean: {d:.5} ns, sum: {d}\n", .{ result.getRuntimeSeconds(), result.getMeanNs(), sum });
    }

    pub fn run() void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator: std.mem.Allocator = gpa.allocator();
        defer _ = gpa.deinit();

        GSetup(allocator) catch {
            @panic("Could not run Global Setup");
        };

        run_benchmark(MapKey.compare_v1, "compare v1");
        run_benchmark(MapKey.compare_v2, "compare v2");
        run_benchmark(MapKey.compare_v3, "compare v3");
        // run_benchmark(MapKey.compare_asm, "compare asm");
    }
};
