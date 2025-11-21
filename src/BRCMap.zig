const builtin = @import("builtin");
const std = @import("std");
const Stat = @import("Stat.zig");
const sso = @import("sso.zig").sso16;

const memeql = @import("root.zig").eqlBytes;

pub fn BRCMap(comptime capacity: comptime_int) type {
    comptime {
        if (capacity <= 0) @compileError("capacity must be > 0");
        if (capacity > std.math.maxInt(isize)) @compileError("capacity must be < maximum isize");
        if (!std.math.isPowerOfTwo(capacity)) @compileError("capacity must be a power of 2");
    }
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        unmanaged: BRCMapUnmanaged(capacity),

        pub inline fn count(self: *const Self) usize {
            return self.unmanaged.count;
        }

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .unmanaged = try BRCMapUnmanaged(capacity).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i32) void {
            self.unmanaged.addOrUpdate(key, value);
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) !void {
            self.unmanaged.addOrMerge(key, stat);
        }

        /// Merges the key / value pairs from `other` into `self`
        pub fn merge(self: *Self, other: *Self) void {
            self.unmanaged.merge(&other.unmanaged);
        }
    };
}

pub fn BRCMapUnmanaged(comptime capacity: comptime_int) type {
    comptime if (capacity > std.math.maxInt(u32)) @compileError("capacity must fit inside a u32");
    return struct {
        const Self = @This();
        count: usize = 0,
        // TODO Test if it's better to keep these directly on the struct
        keys: []sso = undefined,
        values: []Stat = undefined,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const r: Self = Self{
                .count = 0,
                .keys = try allocator.alloc(sso, capacity),
                .values = try allocator.alloc(Stat, capacity),
            };
            @memset(r.keys, sso{});
            @memset(r.values, Stat{});
            return r;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.keys);
            allocator.free(self.values);
        }

        inline fn getKeyHash(key: []const u8) u64 {
            return std.hash.XxHash3.hash(0, key);
        }

        inline fn getBaseIndex(key: []const u8) usize {
            const hash: usize = getKeyHash(key);
            return hash & comptime (capacity - 1);
        }

        /// Finds the index key has / should have in self.keys. The index is returned in the `out` parameter
        /// returns `true` if the key was found otherwise `false`
        fn findKeyIndex(self: *const Self, key: []const u8, out: *u32) bool {
            var index: u32 = @truncate(getBaseIndex(key));
            for (0..capacity) |_| {
                if (self.keys[index].isEmpty()) {
                    @branchHint(.unlikely);
                    out.* = index;
                    return false;
                } else if (self.keys[index].eqlStr(key)) {
                    @branchHint(.likely);
                    out.* = index;
                    return true;
                } else {
                    @branchHint(.cold);
                    index = (index + 1) % capacity;
                }
            }
            unreachable;
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i16) void {
            var index: u32 = undefined;
            if (self.findKeyIndex(key, &index)) {
                @branchHint(.likely);
                std.debug.assert(self.keys[index].isNotEmpty());
                self.values[index].add(value);
            } else {
                @branchHint(.unlikely);
                self.keys[index].set(key);
                self.values[index].set(value);
                self.count += 1;
            }
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) void {
            var index: u32 = undefined;
            if (self.findKeyIndex(key, &index)) {
                @branchHint(.likely);
                std.debug.assert(self.keys[index].isNotEmpty());
                self.values[index].mergeWith(stat);
            } else {
                @branchHint(.unlikely);
                self.keys[index].set(key);
                self.values[index] = stat.*;
                self.count += 1;
            }
        }

        /// Merges the key / value pairs from `other` into `self`
        pub fn merge(self: *Self, other: *Self) void {
            for (other.keys, other.values) |*k, *v| if (k.isNotEmpty()) self.addOrMerge(k.get(), v);
        }
    };
}

test BRCMapUnmanaged {
    std.debug.print("Running test BRCMapUnmanaged\n", .{});
    inline for (8..24) |i| {
        _ = BRCMapUnmanaged(1 << i);
    }
}
