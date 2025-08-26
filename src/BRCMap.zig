const builtin = @import("builtin");
const std = @import("std");
const Stat = @import("Stat.zig");
const sso = @import("sso.zig");

inline fn memeql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.ptr == b.ptr) return true;

    const vlen: comptime_int = std.simd.suggestVectorLength(u8) orelse 8;
    const L: usize = a.len;
    var l: usize = a.len;
    while ((L - l) >= vlen) {
        const va_ptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&a[l]);
        const vb_ptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&b[l]);
        const veql: @Vector(vlen, bool) = va_ptr.* == vb_ptr.*;
        const eql: bool = @reduce(.And, veql);
        if (!eql) return false;
        l += vlen;
    }
    while (l < L) : (l += 1) if (a[l] != b[l]) return false;
    return true;
}

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
        keys: []?sso = undefined,
        values: []?Stat = undefined,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const r: Self = Self{
                .allocator = allocator,
                .count = 0,
                .keys = try allocator.alloc(?sso, capacity),
                .values = try allocator.alloc(?Stat, capacity),
            };

            @memset(r.keys, null);
            @memset(r.values, null);
            return r;
        }

        pub fn deinit(self: *Self) void {
            for (self.keys) |key| if (key != null) @constCast(&key.?).destroy(self.allocator);
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

        const KeyIndexResultType = enum {
            found,
            new,
        };
        const KeyIndexResult = union(KeyIndexResultType) {
            found: usize,
            new: usize,
        };

        fn findKeyIndex(self: *const Self, key: []const u8) KeyIndexResult {
            const base_index: usize = getBaseIndex(key);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset) % capacity;
                if (self.keys[index] == null) return KeyIndexResult{ .new = index };
                if (memeql(key, self.keys[index].?.get())) return KeyIndexResult{ .found = index };
            }
            unreachable;
        }

        pub fn addOrUpdate(self: *Self, key: []const u8, value: i32) !void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index] != null);
                    std.debug.assert(self.values[index] != null);
                    self.values[index].?.add(value);
                },
                .new => |index| {
                    self.keys[index] = try sso.clone(self.allocator, key);
                    self.values[index] = Stat.init(value);
                    self.count += 1;
                },
            }
        }

        pub fn addOrMerge(self: *Self, key: []const u8, stat: *const Stat) !void {
            switch (self.findKeyIndex(key)) {
                .found => |index| {
                    std.debug.assert(self.keys[index] != null);
                    std.debug.assert(self.values[index] != null);
                    self.values[index].?.mergeWith(stat);
                },
                .new => |index| {
                    self.keys[index] = try sso.clone(self.allocator, key);
                    self.values[index] = stat.*;
                    self.count += 1;
                },
            }
        }
    };
}
