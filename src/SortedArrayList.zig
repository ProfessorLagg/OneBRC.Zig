const builtin = @import("builtin");
const std = @import("std");

pub fn ComparisonFn(comptime T: type) type {
    return fn (a: T, b: T) std.math.Order;
}

pub fn SortedArrayList(comptime T: type, comptime comparison: ComparisonFn(T)) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        base_list: std.ArrayListUnmanaged(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{ .allocator = allocator, .base_list = .{} };
        }

        pub fn deinit(self: *Self) void {
            self.base_list.deinit(self.allocator);
        }

        fn linearSearchInsert(items: []const T, item: T) usize {
            if (items.len == 0) return 0;

            var i: usize = 0;
            loop: switch (comparison(item, items[i])) {
                .eq, .gt => return i,
                .lt => {
                    i += 1;
                    if (i >= items.len) return i;
                    continue :loop comparison(item, items[i]);
                },
            }
            unreachable;
        }

        pub fn insert(self: *Self, item: T) !isize {
            const insertAtIndex: usize = std.sort.binarySearch(T, T, comparison) orelse linearSearchInsert(self.base_list.items, item);
            self.base_list.insert(self.allocator, insertAtIndex);
        }
    };
}
