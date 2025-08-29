const builtin = @import("builtin");
const std = @import("std");

const backend_supports_vectors = switch (builtin.zig_backend) {
    .stage2_llvm, .stage2_c => true,
    else => false,
};

pub fn SplitIterator(comptime delimiter: u8) type {
    return struct {
        const Self = @This();
        buffer: []const u8,

        fn indexOfDelim(slice: []const u8) ?usize {
            @setRuntimeSafety(false);

            var i: usize = 0;
            const Vec32 = @Vector(32, u8);
            const mask32: Vec32 = comptime (@as(Vec32, @splat(delimiter)));
            while ((slice.len - i) <= 32) {
                const block: *align(1) const Vec32 = @ptrCast(slice[i..][0..32]);
                const matches = block.* == mask32;
                if (@call(.always_inline, std.simd.firstTrue, .{matches})) |I| {
                    return i + I;
                }
                i += 32;
            }

            const Vec16 = @Vector(16, u8);
            const mask16: Vec16 = comptime (@as(Vec16, @splat(delimiter)));
            while ((slice.len - i) <= 16) {
                const block: *align(1) const Vec16 = @ptrCast(slice[i..][0..16]);
                const matches = block.* == mask16;
                if (@call(.always_inline, std.simd.firstTrue, .{matches})) |I| {
                    return i + I;
                }
                i += 16;
            }

            for (slice[i..], i..) |c, j| if (c == delimiter) return j;
            return null;
        }

        pub fn next(self: *Self) ?[]const u8 {
            if (self.buffer.len == 0) return null;
            // TODO i can optimize this better because i know the delimiter at comptime
            // const si: usize = std.mem.indexOfScalar(u8, self.buffer, delimiter) orelse self.buffer.len;
            const si: usize = indexOfDelim(self.buffer) orelse self.buffer.len;
            const result: []const u8 = self.buffer[0..si];
            self.buffer = self.buffer[@min(self.buffer.len, si + 1)..];
            return result;
        }

        test "next" {
            const cities = @embedFile("cities.txt");
            var std_iter = std.mem.splitScalar(u8, cities, delimiter);
            var new_iter = Self{ .buffer = cities };

            var both_null: bool = false;
            while (!both_null) {
                const std_item = std_iter.next();
                const new_item = new_iter.next();

                try std.testing.expectEqual(std_item, new_item);

                both_null = (std_item == null) and (new_item == null);
            }
        }
    };
}
