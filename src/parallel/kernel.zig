const std = @import("std");
const Allocator = std.mem.Allocator;
const parallelUtils = @import("parallelUtils.zig");

pub fn ParallelKernel(comptime Tsrc: type, comptime Tdst: type, comptime kernelFunc: fn (in: Tsrc) Tdst) type {
    const align_src: u29 = comptime blk: {
        const s: u29 = @sizeOf(Tsrc);
        const l: u29 = std.math.log2(s);
        const r: u29 = std.math.pow(u29, 2, l);
        break :blk r;
    };
    const align_dst: u29 = comptime blk: {
        const s: u29 = @sizeOf(Tdst);
        const l: u29 = std.math.log2(s);
        const r: u29 = std.math.pow(u29, 2, l);
        break :blk r;
    };

    return struct {
        const Self = @This();
        count: usize,
        inputs: []Tsrc,
        results: []Tdst,
        allocator: Allocator,

        pub fn init(allocator: Allocator, len: usize) !Self {
            return Self{ // NOWRAP
                .allocator = allocator,
                .count = 0,
                .inputs = try allocator.alignedAlloc(Tsrc, align_src, len),
                .results = try allocator.alignedAlloc(Tdst, align_dst, len),
            };
        }
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.inputs);
            self.allocator.free(self.results);
        }

        pub fn writeInput(self: *Self, v: Tsrc) bool {
            self.inputs[self.count] = v;
            self.count += 1;
            return self.count == self.inputs.len;
        }

        pub inline fn resetCount(self: *Self) void {
            self.count = 0;
        }

        fn threadFunc(
            src: []const Tsrc,
            dst: []Tdst,
            input_count: usize,
            thread_offset: usize,
            thread_count: usize,
        ) void {
            var i: usize = thread_offset;
            while (i < input_count) : (i += thread_count) {
                dst[i] = kernelFunc(src[i]);
            }
        }

        pub fn run(self: *Self) !void {
            if (self.count == 0) {
                return;
            }

            const max_thread_count = parallelUtils.get_max_thread_count();
            var threads: []std.Thread = try self.allocator.alloc(std.Thread, max_thread_count);
            defer self.allocator.free(threads);

            for (0..threads.len) |i| {
                threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ self.inputs, self.results, self.count, i, max_thread_count });
            }

            for (0..threads.len) |i| {
                threads[i].join();
            }
        }
    };
}
