const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const ut = @import("utils.zig");
const DynamicArray = @import("DynamicArray.zig").DynamicArray;
const MapVal = @import("BRCMapVal.zig");

pub fn BRCHashMap(comptime uint: type, comptime hashFn: fn ([]const u8) uint) type {
    // TODO Verify that hashInt is an unsigned, power of 2, integer
    comptime {
        const ti: std.builtin.Type = @typeInfo(uint);
        const errmsg_uint = "Expected unsigned power of 2 bitwidth integer, but found " ++ @typeName(uint);
        if (ti != .int) @compileError(errmsg_uint);
        if (ti.int.signedness != .unsigned) @compileError(errmsg_uint);
        if (@bitSizeOf(uint) == 0 or std.math.isPowerOfTwo(@bitSizeOf(uint)) == false) @compileError(errmsg_uint);
    }

    _ = &hashFn;
    return struct {
        const Self = @This();
        pub const Entry = struct {
            hash: uint = 0,
            keyptr: [*]const u8 = undefined,
            keylen: u8 = 0,
            value: MapVal = MapVal.None,

            pub fn getKeyString(self: *const Entry) []const u8 {
                @setRuntimeSafety(false);
                var r: []const u8 = undefined;
                r.ptr = self.keyptr;
                r.len = self.keylen;
                return r;
            }

            /// Sets `self.keyptr` and `self.keylen`.
            /// Caller asserts that`keyString.len <= std.math.maxInt(@TypeOf(self.keylen))`
            pub fn setKeyString(self: *Entry, keyString: []const u8) void {
                @setRuntimeSafety(false);
                std.debug.assert(keyString.len <= std.math.maxInt(@TypeOf(self.keylen)));
                self.keyptr = keyString.ptr;
                self.keylen = @truncate(keyString.len);
            }
        };

        allocator: Allocator,
        entries: []const Entry = ut.meta.zeroedSlice(Entry),
        lock: std.Thread.Mutex = .{},
        count: usize = 0,
        collisionCount: usize = 0,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            if (capacity == 0) return error.CapacityCannotBeZero;
            if (std.math.isPowerOfTwo(capacity) == false) return error.CapacityNotPowerOf2;

            const entries: []Entry = try allocator.alloc(Entry, capacity);
            @memset(entries, Entry{});
            return Self{
                .allocator = allocator,
                .entries = entries,
            };
        }
        pub fn freeKeys(self: *Self) void {
            for (self.entries) |e| {
                if (e.keylen == 0) continue;
                self.allocator.free(e.getKeyString());
            }
        }
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.entries);
        }

        /// Returns the number of keys that collided when inserted as a number between 0 and 1
        pub fn getCollisionPercent(self: *const Self) f64 {
            @setRuntimeSafety(false);
            @constCast(self).lock.lock();
            defer @constCast(self).lock.unlock();

            const count_f: f64 = @floatFromInt(@max(1, self.count));
            const collisions_f: f64 = @floatFromInt(self.collisionCount);
            return collisions_f / count_f;
        }

        /// If `key` is found in the map, adds `val` to the corresponding `MapVal`.
        /// Else inserts a new `Entry` into the map with a clone of `key`
        /// Caller asserts that `hashFn(key) == hash`.
        pub fn addClonePreHashed(self: *Self, key: []const u8, val: i64, hash: uint) !void {
            std.debug.assert(hashFn(key) == hash);
            std.debug.assert(val >= -999);
            std.debug.assert(val <= 999);
            std.debug.assert(key.len >= 1);
            std.debug.assert(key.len <= 100); // 1brc contraint on keylen

            if (self.count == self.entries.len) {
                // TODO Resize instead of returning an error
                return error.MapFull;
            }

            const baseIndex: usize = @as(usize, @intCast(hash)) & (self.entries.len - 1);
            var collided: bool = false;

            self.lock.lock();
            defer {
                self.collisionCount += @intFromBool(collided);
                self.lock.unlock();
            }
            for (0..self.entries.len) |i| {
                const index: usize = (baseIndex + i) % self.entries.len;
                const entry_ptr: *Entry = @constCast(&self.entries[index]);
                if (self.entries[index].keylen == 0) {
                    // Found empty slot
                    const keyclone: []const u8 = try ut.mem.clone(u8, self.allocator, key);
                    entry_ptr.hash = hash;
                    entry_ptr.setKeyString(keyclone);
                    entry_ptr.value = MapVal.create(val);
                    self.count += 1;
                    return;
                }

                const keystr: []const u8 = self.entries[index].getKeyString();
                if (std.mem.eql(u8, key, keystr)) {
                    // Found matching slot
                    entry_ptr.value.add(val);
                    return;
                }

                std.log.debug("Keys collided! hash: 0x{X}, key: \"{s}\"", .{ hash, key });
                collided = true;
            }

            unreachable;
        }

        /// If `key` is found in the map, adds `val` to the corresponding `MapVal`.
        /// Else inserts a new `Entry` into the map with a clone of `key`
        pub fn addClone(self: *Self, key: []const u8, val: i64) void {
            const hash: uint = hashFn(key);
            self.addClonePreHashed(key, val, hash);
        }

        const Iterator = struct {
            entries: []const Entry = undefined,
            index: usize = 0,

            pub fn first(self: *Iterator) ?*const Entry {
                self.index = 0;
                return self.next();
            }
            pub fn next(self: *Iterator) ?*const Entry {
                while (self.index < self.entries.len) {
                    const entry_ptr: *const Entry = &self.entries[self.index];
                    self.index += 1;
                    if (entry_ptr.keylen != 0) return entry_ptr;
                }
                return null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .entries = self.entries };
        }
    };
}
