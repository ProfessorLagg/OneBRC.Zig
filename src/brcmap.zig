const builtin = @import("builtin");
const std = @import("std");
const ut = @import("utils.zig");
const Order = std.math.Order;
const DynamicBuffer = @import("DynamicBuffer.zig");
const DynamicArray = @import("DynamicArray.zig").DynamicArray;

const Vecstr8 = @import("vecstr.zig").Vecstr8;
const Vecstr16 = @import("vecstr.zig").Vecstr16;
const Vecstr32 = @import("vecstr.zig").Vecstr32;
const Vecstr64 = @import("vecstr.zig").Vecstr64;
const Vecstr128 = @import("vecstr.zig").Vecstr128;

const log = std.log.scoped(.BRCMap);

pub const MapVal = struct {
    pub const FinalMapVal = struct {
        mean: f64 = 0,
        min: f64 = 0,
        max: f64 = 0,
    };
    pub const None: MapVal = .{};

    sum: i64 = 0,
    count: u32 = 0,
    min: i16 = std.math.maxInt(i16),
    max: i16 = std.math.minInt(i16),
    pub inline fn add(self: *MapVal, v: i64) void {
        @setRuntimeSafety(false);
        self.sum += v;
        self.count += 1;
        const v16: i16 = @intCast(v);
        self.min = @min(self.min, v16);
        self.max = @max(self.max, v16);
    }
    pub inline fn merge(self: *MapVal, other: *const MapVal) void {
        @setRuntimeSafety(false);
        self.sum += other.sum;
        self.count += other.count;
        self.min = @min(self.min, other.min);
        self.max = @max(self.max, other.max);
    }
    pub inline fn finalize(self: *const MapVal) FinalMapVal {
        @setRuntimeSafety(false);
        @setFloatMode(.optimized);
        const sum_f: f64 = @floatFromInt(self.sum);
        const count_f: f64 = @floatFromInt(self.count);
        const min_f: f64 = @floatFromInt(self.min);
        const max_f: f64 = @floatFromInt(self.max);
        return .{
            .mean = sum_f / (count_f * 10.0),
            .min = min_f / 10.0,
            .max = max_f / 10.0,
        };
    }
};

fn SubMap(comptime StringLength: comptime_int) type {
    return struct {
        const Vecstr = switch (StringLength) {
            8 => Vecstr8,
            16 => Vecstr16,
            32 => Vecstr32,
            64 => Vecstr64,
            128 => Vecstr128,
            else => unreachable,
        };
        const Self = @This();
        allocator: std.mem.Allocator,
        keybuf: []Vecstr,
        valbuf: []MapVal,
        keys: []Vecstr,
        vals: []MapVal,

        fn init(parent: *const BRCMap) Self {
            return Self{
                .allocator = parent.allocator,
                .keybuf = std.mem.zeroes([]Vecstr),
                .keys = std.mem.zeroes([]Vecstr),
                .valbuf = std.mem.zeroes([]MapVal),
                .vals = std.mem.zeroes([]MapVal),
            };
        }
        fn deinit(self: *Self) void {
            self.allocator.free(self.keybuf);
            self.allocator.free(self.valbuf);
        }

        inline fn count(self: *const Self) usize {
            std.debug.assert(self.keys.len == self.vals.len);
            return self.keys.len;
        }

        inline fn _capacity(self: *const Self) usize {
            std.debug.assert(self.keybuf.len == self.valbuf.len);
            return self.keybuf.len;
        }

        fn ensureCapacity(self: *Self, capacity: usize) !void {
            if (self._capacity() >= capacity) return;
            const new_capacity: usize = ut.math.ceilPowerOfTwo(usize, capacity);
            if (self._capacity() == 0) {
                // There is currently nothing allocated
                self.keybuf = try self.allocator.alloc(Vecstr, new_capacity);
                self.valbuf = try self.allocator.alloc(MapVal, new_capacity);
                self.keys = self.keybuf[0..0];
                self.vals = self.valbuf[0..0];
                return;
            }
            _ = try ut.mem.resize(Vecstr, self.allocator, &self.keybuf, new_capacity);
            _ = try ut.mem.resize(MapVal, self.allocator, &self.valbuf, new_capacity);
            self.keys.ptr = self.keybuf.ptr;
            self.vals.ptr = self.valbuf.ptr;
        }

        fn insert(self: *Self, index: usize, key: Vecstr, val: MapVal) !void {
            if (index > self.count()) return error.IndexOutOfRange;
            try self.ensureCapacity(self.count() + 1);

            // We shift keys and vals seperately to hopefully get more out of CPU Cache
            self.keys.len += 1;
            var i = self.keys.len - 1;
            while (i > index) : (i -= 1) self.keys[i] = self.keys[i - 1];
            self.keys[index] = key;

            self.vals.len += 1;
            i = self.vals.len - 1;
            while (i > index) : (i -= 1) self.vals[i] = self.vals[i - 1];
            self.vals[index] = val;
        }

        inline fn append(self: *Self, key: Vecstr, val: MapVal) !void {
            try self.insert(self.count(), key, val);
        }

        fn searchInsert(self: *const Self, item: Vecstr) isize {
            ut.debug.print("\nbinary searching for key: \"{s}\"\n", .{item.asSlice()});
            std.debug.assert(self.count() > 0);

            var L: isize = 0;
            var R: isize = @as(isize, @intCast(self.count())) - 1;

            var m: isize = L + @divFloor(R - L, 2);
            var k: Vecstr = self.keys[@abs(m)];
            var c: i8 = Vecstr.compare(&k, &item);
            loop: switch (c) {
                0 => return m,
                -1 => {
                    ut.debug.print("\tk{d}: \"{s}\" <  key: \"{s}\"\n", .{ m, k.asSlice(), item.asSlice() });
                    R = m - 1;
                    if (L > R) break :loop;

                    m = L + @divFloor(R - L, 2);
                    k = self.keys[@abs(m)];
                    c = Vecstr.compare(&k, &item);
                    continue :loop c;
                },
                1 => {
                    ut.debug.print("\tk{d}: \"{s}\" >  key: \"{s}\"\n", .{ m, k.asSlice(), item.asSlice() });
                    L = m + 1;
                    if (L > R) break :loop;

                    m = L + @divFloor(R - L, 2);
                    k = self.keys[@abs(m)];
                    c = Vecstr.compare(&k, &item);
                    continue :loop c;
                },
                else => unreachable,
            }

            m = L;
            while (m < self.count()) : (m += 1) {
                k = self.keys[@abs(m)];
                c = Vecstr.compare(&item, &k);
                switch (c) {
                    0 => {
                        if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                            ut.debug.print("Keys:\n", .{});
                            for (0..self.count()) |j| {
                                const keyvec: Vecstr = self.keys[j];
                                ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keyvec.asSlice() });
                            }
                            std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ item.asSlice(), m });
                        } else @panic("Binary Search Failed to find key!");
                    },
                    1 => break,
                    -1 => continue,
                    else => unreachable,
                }
            }

            return ~m;
        }

        fn findOrInsert(self: *Self, key: Vecstr) !*MapVal {
            const cnt = self.count();
            if (cnt == 0) {
                try self.append(key, MapVal.None);
                return &self.vals[0];
            }
            const signed = self.searchInsert(key);
            const idx: usize = b: switch (std.math.sign(signed)) {
                0, 1 => @abs(signed),
                -1 => {
                    const c = self.count();
                    const i: usize = @intCast(~signed);
                    std.debug.assert(i <= c);
                    std.debug.assert(i == c or !ut.mem.eqlBytes(key.asSlice(), self.keys[i].asSlice()));
                    try self.insert(i, key, MapVal.None);
                    break :b i;
                },
                else => unreachable,
            };
            return &self.vals[idx];
        }
    };
}

const BRCMap = @This();
allocator: std.mem.Allocator,
sub8: SubMap(8),
sub16: SubMap(16),
sub32: SubMap(32),
sub64: SubMap(64),
sub128: SubMap(128),

pub fn init(allocator: std.mem.Allocator) BRCMap {
    var r = BRCMap{
        .allocator = allocator,
        .sub8 = undefined,
        .sub16 = undefined,
        .sub32 = undefined,
        .sub64 = undefined,
        .sub128 = undefined,
    };
    r.sub8 = @TypeOf(r.sub8).init(&r);
    r.sub16 = @TypeOf(r.sub16).init(&r);
    r.sub32 = @TypeOf(r.sub32).init(&r);
    r.sub64 = @TypeOf(r.sub64).init(&r);
    r.sub128 = @TypeOf(r.sub128).init(&r);
    return r;
}
pub fn deinit(self: *BRCMap) void {
    self.sub8.deinit();
    self.sub16.deinit();
    self.sub32.deinit();
    self.sub64.deinit();
    self.sub128.deinit();
}

pub inline fn count(self: *const BRCMap) usize {
    return self.sub8.count() +
        self.sub16.count() +
        self.sub32.count() +
        self.sub64.count() +
        self.sub128.count();
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    if (key.len <= 8) return self.sub8.findOrInsert(Vecstr8.create(key));
    if (key.len <= 16) return self.sub16.findOrInsert(Vecstr16.create(key));
    if (key.len <= 32) return self.sub32.findOrInsert(Vecstr32.create(key));
    if (key.len <= 64) return self.sub64.findOrInsert(Vecstr64.create(key));
    if (key.len <= 128) return self.sub128.findOrInsert(Vecstr128.create(key));
    unreachable;
}

pub const MapEntry = struct {
    key: []const u8,
    val: *const MapVal,
};

pub const MapIterator = struct {
    map: *const BRCMap,
    idx: usize = 0,

    pub fn next(self: *MapIterator) ?MapEntry {
        var result: MapEntry = undefined;
        const high8 = self.map.sub8.count();
        const high16 = high8 + self.map.sub16.count();
        const high32 = high16 + self.map.sub32.count();
        const high64 = high32 + self.map.sub64.count();
        const high128 = high64 + self.map.sub64.count();

        if (self.idx < high8) {
            result = MapEntry{
                .key = self.map.sub8.keys[self.idx].asSlice(),
                .val = &self.map.sub8.vals[self.idx],
            };
        } else if (self.idx < high16) {
            result = MapEntry{
                .key = self.map.sub8.keys[self.idx - high8].asSlice(),
                .val = &self.map.sub8.vals[self.idx - high8],
            };
        } else if (self.idx < high32) {
            result = MapEntry{
                .key = self.map.sub8.keys[self.idx - high16].asSlice(),
                .val = &self.map.sub8.vals[self.idx - high16],
            };
        } else if (self.idx < high64) {
            result = MapEntry{
                .key = self.map.sub8.keys[self.idx - high32].asSlice(),
                .val = &self.map.sub8.vals[self.idx - high32],
            };
        } else if (self.idx < high128) {
            result = MapEntry{
                .key = self.map.sub8.keys[self.idx - high64].asSlice(),
                .val = &self.map.sub8.vals[self.idx - high64],
            };
        } else return null;

        self.idx += 1;
        return result;
    }
};

pub fn iterator(self: *const BRCMap) MapIterator {
    return MapIterator{ .map = self };
}

/// Merges `other` into `self`
pub fn mergeWith(self: *BRCMap, other: *const BRCMap) !void {
    for (0..other.sub8.count()) |i| (try self.sub8.findOrInsert(other.sub8.keys[i])).merge(&other.sub8.vals[i]);
    for (0..other.sub16.count()) |i| (try self.sub16.findOrInsert(other.sub16.keys[i])).merge(&other.sub16.vals[i]);
    for (0..other.sub32.count()) |i| (try self.sub32.findOrInsert(other.sub32.keys[i])).merge(&other.sub32.vals[i]);
    for (0..other.sub64.count()) |i| (try self.sub64.findOrInsert(other.sub64.keys[i])).merge(&other.sub64.vals[i]);
    for (0..other.sub128.count()) |i| (try self.sub128.findOrInsert(other.sub128.keys[i])).merge(&other.sub128.vals[i]);
}
