const builtin = @import("builtin");
const std = @import("std");

pub fn SplitIterator(comptime delimiter: u8) type {
    return struct {
        const Self = @This();
        buffer: []const u8,
        pub fn next(self: *Self) ?[]const u8 {
            if (self.buffer.len == 0) return null;
            // TODO i can optimize this better because i know the delimiter at comptime
            const si: usize = std.mem.indexOfScalar(u8, self.buffer, delimiter) orelse self.buffer.len;
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
