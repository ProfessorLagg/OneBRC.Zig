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

        const KeyIndexResultType = enum {
            found,
            new,
        };
        const KeyIndexResult = union(KeyIndexResultType) {
            found: u32,
            new: u32,
        };

        fn findKeyIndex(self: *const Self, key: []const u8) KeyIndexResult {
            @setRuntimeSafety(false);
            const base_index: u32 = @truncate(getBaseIndex(key));
            var offset: u32 = 0;
            while (offset < capacity) : (offset += 1) {
                const index: u32 = (base_index + offset) % capacity;
                const key_str = self.keys[index].get();
                if (key_str.len == 0) {
                    return KeyIndexResult{ .new = @truncate(index) };
                } else if (std.mem.eql(u8, key_str, key)) {
                    return KeyIndexResult{ .found = @truncate(index) };
                }
            }
            // std.log.err("Could not insert key: \"{s}\" into BRCMap", .{key});
            unreachable;
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i32) void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index].isNotEmpty());
                    self.values[index].add(value);
                },
                .new => |index| {
                    self.keys[index].set(key);
                    // self.values[index] = Stat.init(value);
                    self.values[index].set(value);
                    self.count += 1;
                },
            }
        }

        pub fn addOrUpdateCloned(self: *Self, gpa: std.mem.Allocator, key: []const u8, value: i32) !void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index].isNotEmpty());
                    self.values[index].add(value);
                },
                .new => |index| {
                    if (sso.isLargeLen(key.len)) {
                        const keyclone = try gpa.alloc(u8, key.len);
                        @memcpy(keyclone[0..], key[0..]);
                        self.keys[index].set(keyclone);
                    } else {
                        self.keys[index].set(key);
                    }

                    self.values[index] = Stat.init(value);
                    self.count += 1;
                },
            }
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index].isNotEmpty());
                    self.values[index].mergeWith(stat);
                },
                .new => |index| {
                    self.keys[index].set(key);
                    self.values[index] = stat.*;
                    self.count += 1;
                },
            }
        }

        pub fn addOrMergeCloned(self: *Self, key: []const u8, stat: *const Stat, gpa: std.mem.Allocator) !void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index].isNotEmpty());
                    self.values[index].mergeWith(stat);
                },
                .new => |index| {
                    if (sso.isLargeLen(key.len)) {
                        const keyclone = try gpa.alloc(u8, key.len);
                        @memcpy(keyclone[0..], key[0..]);
                        self.keys[index].set(keyclone);
                    } else {
                        self.keys[index].set(key);
                    }
                    self.values[index] = stat.*;
                    self.count += 1;
                },
            }
        }

        /// Merges the key / value pairs from `other` into `self`
        pub fn merge(self: *Self, other: *Self) void {
            @setRuntimeSafety(false);
            for (other.keys, other.values) |*k, *v| if (k.isNotEmpty()) self.addOrMerge(k.get(), v);
        }

        /// Merges the key / value pairs from `other` into `self`
        pub fn mergeCloned(self: *Self, other: *Self, gpa: std.mem.Allocator) !void {
            @setRuntimeSafety(false);
            for (other.keys, other.values) |*k, *v| if (k.isNotEmpty()) try self.addOrMergeCloned(k.get(), v, gpa);
        }
    };
}
