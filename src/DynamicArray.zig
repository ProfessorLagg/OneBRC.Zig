const builtin = @import("builtin");
const std = @import("std");
const ut = @import("utils.zig");

pub fn DynamicArray(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        capacity: usize,
        items: []T,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .ptr = @ptrFromInt(0),
                .capacity = 0,
                .items = std.mem.zeroes([]T),
            };
        }
        pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            var r: Self = Self.init(allocator);
            try r.ensureCapacity(capacity);
            return r;
        }
        pub fn denit(self: *Self) void {
            self.allocator.free(self.ptr[0..self.capacity]);
        }
        pub fn ensureCapacity(self: *Self, capacity: usize) !void {
            if (self.capacity >= capacity) return;

            const new_capacity: usize = ut.math.ceilPowerOfTwo(usize, capacity);
            if (self.capacity == 0) {
                // There is currently nothing allocated
                const new_buffer: []T = try self.allocator.alloc(T, new_capacity);
                self.items.ptr = new_buffer.ptr;
                self.capacity = new_buffer.len;
                return;
            }
            var buffer: []T = self.items.ptr[0..self.capacity];
            _ = try ut.mem.resize(T, self.allocator, &buffer, new_capacity);
            self.items.ptr = buffer.ptr;
            self.capacity = buffer.len;
        }
        pub fn append(self: *Self, item: T) !void {
            try self.ensureCapacity(self.items.len + 1);
            self.items.len += 1;
            self.items[self.items.len - 1] = item;
        }
        pub fn insert(self: *Self, item: T, index: usize) !void {
            if (index > self.items.len) return error.IndexOutOfRange;
            self.ensureCapacity(self.items.len + 1);

            self.items.len += 1;
            for (self.items.len..index + 1) |i| self.items[i] = self.items[i - 1];
            self.items[index] = item;
        }
    };
}
