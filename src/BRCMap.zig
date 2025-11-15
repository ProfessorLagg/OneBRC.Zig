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

        const KeyIndexResult = struct {
            isNew: bool,
            index: u32,

            pub inline fn setFound(self: *@This(), idx: u32) void {
                self.index = idx;
                self.isNew = false;
            }

            pub inline fn setNew(self: *@This(), idx: u32) void {
                self.index = idx;
                self.isNew = true;
            }
        };

        test KeyIndexResult {
            var kir: KeyIndexResult = undefined;
            const arr: []u8 = b: {
                var r: []u8 = undefined;
                r.len = @sizeOf(KeyIndexResult);
                r.ptr = @ptrCast(&kir);
                break :b r;
            };
            var i: u32 = 0;
            while (i < capacity) : (i += 1) {
                @memset(arr[0..], 0);
                kir.setFound(i);
                try std.testing.expectEqual(kir.isNew, false);
                try std.testing.expectEqual(kir.index, i);

                @memset(arr[0..], 0);
                kir.setNew(i);
                try std.testing.expectEqual(kir.isNew, true);
                try std.testing.expectEqual(kir.index, i);
            }
        }

        fn findKeyIndex(self: *const Self, key: []const u8) KeyIndexResult {
            var r: KeyIndexResult = .{
                .isNew = false,
                .index = @truncate(getBaseIndex(key)),
            };
            for (0..capacity) |_| {
                if (self.keys[r.index].isEmpty()) {
                    @branchHint(.unlikely);
                    r.isNew = true;
                    return r;
                } else if (self.keys[r.index].eqlStr(key)) { 
                    @branchHint(.likely);
                    return r;
                } else {
                    @branchHint(.cold);
                    r.index = (r.index + 1) % capacity;
                }
            }
            unreachable;
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i16) void {
            const ki = self.findKeyIndex(key);
            if (ki.isNew) {
                @branchHint(.unlikely);
                self.keys[ki.index].set(key);
                self.values[ki.index].set(value);
                self.count += 1;
            } else {
                @branchHint(.likely);
                std.debug.assert(self.keys[ki.index].isNotEmpty());
                self.values[ki.index].add(value);
            }
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) void {
            const ki = self.findKeyIndex(key);
            if (ki.isNew) {
                @branchHint(.unlikely);
                self.keys[ki.index].set(key);
                self.values[ki.index] = stat.*;
                self.count += 1;
            } else {
                @branchHint(.likely);
                std.debug.assert(self.keys[ki.index].isNotEmpty());
                self.values[ki.index].mergeWith(stat);
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
