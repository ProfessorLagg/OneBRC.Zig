const std = @import("std");

const kernel = @import("kernel.zig");
const ThreadPool = @import("pool.zig").ThreadPool;
pub usingnamespace kernel;
pub usingnamespace ThreadPool;

test "ThreadPool" {
    try TestThreadPool();
}
pub fn TestThreadPool() !void {
    // Arrange
    const len: usize = 16;
    var values: [len]u32 = blk: {
        var r: [len]u32 = undefined;
        for (0..r.len) |i| {
            r[i] = @intCast(i);
        }
        break :blk r;
    };

    var threadSafe = std.heap.ThreadSafeAllocator{ .child_allocator = std.heap.page_allocator, .mutex = .{} };
    var arena = std.heap.ArenaAllocator.init(threadSafe.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    var threadPool = ThreadPool.init(allocator);
    defer threadPool.deinit();

    const LocalContext = struct { // NOWRAP
        const Self = @This();
        in: *[len]u32,
        out: *[len * len]u64,
        i: usize,
        j: usize,
        idx: usize,
        pub fn taskFn(ctx: ?*anyopaque) void {
            if (ctx == null) {
                return;
            }
            const self: *Self = @alignCast(@ptrCast(ctx.?));
            self.out[self.idx] = action(self.in[self.i], self.in[self.j]);
            std.log.debug("Hello from taskFn #{d}", .{self.idx});
        }
        pub fn action(a: u32, b: u32) u64 {
            const a64: u64 = @intCast(a);
            const b64: u64 = @intCast(b);
            return (a64 << 32) | b64;
        }
    };
    var control: [len * len]u64 = undefined;
    var output: [len * len]u64 = undefined;

    // Act
    for (0..len) |i| {
        for (0..len) |j| {
            const idx: usize = i * len + j;
            control[idx] = LocalContext.action(values[i], values[j]);

            const ctx: *LocalContext = try allocator.create(LocalContext);

            ctx.in = &values;
            ctx.out = &output;
            ctx.i = i;
            ctx.j = j;
            ctx.idx = idx;

            threadPool.schedule(ctx, LocalContext.taskFn);
        }
    }

    threadPool.waitAll();

    // Assert
    for (0..control.len) |i| {
        try std.testing.expectEqual(control[i], output[i]);
    }
}
