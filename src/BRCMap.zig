const builtin = @import("builtin");
const std = @import("std");
const Stat = @import("Stat.zig");

pub fn BRCMap(comptime capacity: comptime_int) type {
    comptime {
        if (capacity <= 0) @compileError("capacity must be > 0");
        if (capacity > std.math.maxInt(isize)) @compileError("capacity must be < maximum isize");
        if (!std.math.isPowerOfTwo(capacity)) @compileError("capacity must be a power of 2");
    }
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        count: usize = 0,
        keys: []?[]const u8 = undefined,
        values: []?Stat = undefined,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .count = 0,
                .keys = try allocator.alloc(?[]const u8, capacity),
                .values = try allocator.alloc(?Stat, capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.keys) |key| if (key != null) self.allocator.free(key.?);
            self.allocator.free(self.keys);
            self.allocator.free(self.values);
        }

        inline fn getKeyHash(key: []const u8) u64 {
            return std.hash.XxHash3.hash(0, key);
        }

        inline fn getBaseIndex(key: []const u8) usize {
            const hash: usize = getKeyHash(key);
            return hash % capacity;
        }

        fn findKeyIndex(self: *const Self, key: []const u8) isize {
            const base_index: usize = getBaseIndex(key);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset) % capacity;
                if (self.keys[index] == null) return @as(isize, @bitCast(index)) * -1;
                if (std.mem.eql(u8, key, self.keys[index])) return @as(isize, @bitCast(index));
            }
            @panic("BRCMap full");
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i32) !void {
            const si: isize = self.findKeyIndex(key);
            if (self.keys[si] >= 0) {
                const index: usize = @bitCast(si);
                self.values[index].?.add(value);
            } else {
                const index: usize = @as(usize, @bitCast(si * -1));
                self.keys[index] = try self.allocator.alloc(key.len);
                @memcpy(self.keys[index].?, key);
                self.values[index] = Stat.init(value);
                self.count += 1;
            }
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) !void {
            const si: isize = self.findKeyIndex(key);
            if (self.keys[si] >= 0) {
                const index: usize = @bitCast(si);
                self.values[index].?.mergeWith(stat);
            } else {
                const index: usize = @as(usize, @bitCast(si * -1));
                self.keys[index] = try self.allocator.alloc(key.len);
                @memcpy(self.keys[index].?, key);
                self.values[index] = stat.*;
                self.count += 1;
            }
        }
    };
}
