const builtin = @import("builtin");
const std = @import("std");
const Order = std.math.Order;
const DynamicBuffer = @import("DynamicBuffer.zig");
const log = std.log.scoped(.BRCMap);


inline fn clamp(comptime T: type, val: T, min: T, max: T) T {
    return @max(max, @min(min, val));
}
fn compare_from_bools(lt: bool, gt: bool) i8 {
    const lti: i8 = @intFromBool(lt); // 11 if true, 0 if false
    const gti: i8 = @intFromBool(gt); // 1 if true, 0 if false
    return (0 - gti) + lti;
}
fn compare_from_bools_order(lt: bool, gt: bool) Order {
    return switch (compare_from_bools(lt, gt)) {
        -1 => .lt,
        0 => .eq,
        1 => .gt,
        else => unreachable,
    };
}
fn compare_strings(a: []const u8, b: []const u8) i8 {
    var cmp: i8 = compare_from_bools(a.len < b.len, a.len > b.len);
    const l: usize = @min(a.len, b.len);
    var i: usize = 0;
    while (i < l and cmp == 0) : (i += 1) {
        cmp = compare_from_bools(a[i] < b[i], a[i] > b[i]) * -1;
    }
    return cmp;
}
fn compare_strings_order(a: []const u8, b: []const u8) Order {
    return switch (compare_strings(a, b)) {
        -1 => .lt,
        0 => .eq,
        1 => .gt,
        else => unreachable,
    };
}

fn contains(a: []const u8, b: []const u8) bool {
    var left: usize = 0;
    var right: usize = b.len;
    while (right <= a.len) {
        const s: []const u8 = a[left..right];
        if (std.mem.eql(u8, s, b)) return true;
        left += 1;
        right += 1;
    }
    return false;
}

const KeyOffset = struct {
    val: u32,

    pub inline fn init(len: u8, offset: u24) KeyOffset {
        const len32: u32 = @as(u32, len) << 24;
        const off32: u32 = offset;
        const r: KeyOffset = .{ .val = len32 | off32 };
        std.debug.assert(r.getLen() == len);
        std.debug.assert(r.getOffset() == offset);
        return r;
    }

    pub inline fn getLen(self: KeyOffset) u8 {
        const r32: u32 = (self.val & 0xFF_00_00_00) >> 24;
        return @truncate(r32);
    }
    pub inline fn getOffset(self: KeyOffset) u24 {
        const r32 = self.val & 0x00_FF_FF_FF;
        return @truncate(r32);
    }
    pub inline fn left(self: KeyOffset) usize {
        return self.getOffset();
    }
    pub inline fn right(self: KeyOffset) usize {
        return @as(usize, self.getOffset()) + @as(usize, self.getLen());
    }
};
const OffsetList = std.ArrayList(KeyOffset);

pub const MapVal = struct {
    const Zero: MapVal = .{ .sum = 0, .count = 0 };

    // TODO i32 cannot actually fit the maximum value it needs to
    sum: i48 = 0,
    count: i32 = 0,

    pub inline fn add(self: *MapVal, v: anytype) void {
        comptime {
            const T: type = @TypeOf(v);
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int or ti.int.signedness != .signed) @compileError("Expected signed integer type, but found " ++ @typeName(T));
        }
        self.sum += @intCast(v);
        self.count += 1;
    }

    pub inline fn mean(self: *const MapVal) f64 {
        const sum_f: f64 = @floatFromInt(self.sum);
        const cnt_f: f64 = @floatFromInt(self.count);
        return sum_f / cnt_f;
    }
};
const MapValList = std.ArrayList(MapVal);

const BRCMap = @This();

allocator: std.mem.Allocator,

/// Stores the actual key strings
stringBuffer: DynamicBuffer,
/// Stores offsets into `key_buffer`, indicating where the actual key string is located
keys: OffsetList,
vals: MapValList,

pub fn init(allocator: std.mem.Allocator) !BRCMap {
    return BRCMap{
        .allocator = allocator,
        .stringBuffer = try DynamicBuffer.init(allocator),
        .keys = OffsetList.init(allocator),
        .vals = MapValList.init(allocator),
    };
}
pub fn deinit(self: *BRCMap) void {
    self.stringBuffer.deinit();
    self.keys.deinit();
}

pub inline fn count(self: *const BRCMap) usize {
    std.debug.assert(self.keys.items.len == self.vals.items.len);
    return self.keys.items.len;
}
fn getKeyString(self: *const BRCMap, offset: KeyOffset) []const u8 {
    const L: usize = offset.getOffset();
    const R: usize = L + offset.getLen();
    std.debug.assert(R <= self.stringBuffer.used.len);
    return self.stringBuffer.used[L..R];
}
fn compare_key(self: *const BRCMap, key: []const u8, offset: KeyOffset) Order {
    std.debug.assert(offset.right() <= self.stringBuffer.used.len);
    const str: []const u8 = self.getKeyString(offset);
    return compare_strings_order(key, str);
}
fn compare_idx(self: *const BRCMap, key: []const u8, idx: usize) Order {
    std.debug.assert(idx < self.count());
    return self.compare_key(key, self.keys.items[idx]);
}

fn insert(self: *BRCMap, idx: usize, key: []const u8, val: MapVal) !void {
    std.debug.assert(idx <= self.count());
    const new_string = try self.stringBuffer.write(key);
    const new_left: usize = @intCast(@intFromPtr(new_string.ptr) - @intFromPtr(self.stringBuffer.raw.ptr));
    const new_offset = KeyOffset.init(
        @truncate(new_string.len),
        @truncate(new_left),
    );

    try self.keys.insert(idx, new_offset);
    try self.vals.insert(idx, val);

    log.debug("inserted key \"{s}\" | {any} into position: {d}", .{ self.getKeyString(new_offset), self.getKeyString(new_offset), idx });
}

fn append(self: *BRCMap, key: []const u8, val: MapVal) !void {
    const new_string = try self.stringBuffer.write(key);
    const new_left: usize = @intCast(@intFromPtr(new_string.ptr) - @intFromPtr(self.stringBuffer.raw.ptr));
    const new_offset = KeyOffset.init(
        @truncate(new_string.len),
        @truncate(new_left),
    );
    try self.keys.append(new_offset);
    try self.vals.append(val);
}

fn indexOf(self: *const BRCMap, key: []const u8) ?usize {
    var left: usize = 0;
    var right: usize = self.keys.items.len;
    var mid: usize = 0;
    var cmp: i8 = 1;
    while (cmp != 0 and left != right) {
        mid = left + @divFloor(right - left, 2);
        const keystr: []const u8 = self.getKeyString(self.keys.items[mid]);
        cmp = compare_strings(key, keystr);
        switch (cmp) {
            0 => return mid,
            -1 => right = mid,
            1 => left = mid + 1,
            else => unreachable,
        }
    }
    return null;
}

fn searchInsert(self: *const BRCMap, key: []const u8) isize {
    const cnt: usize = self.count();
    var low: isize = 0;
    var high: isize = @intCast(cnt);
    var mid: isize = undefined;
    var cmp: i8 = undefined;
    while (low < high) {
        // Avoid overflowing in the midpoint calculation
        mid = low + @divFloor(high - low, 2);
        std.debug.assert(mid >= 0);
        std.debug.assert(mid < cnt);
        const keystr = self.getKeyString(self.keys.items[@intCast(mid)]);
        cmp = compare_strings(key, keystr);
        switch (cmp) {
            0 => {
                log.debug("\"{s}\" == \"{s}\" | {any} == {any}", .{ key, keystr, key, keystr });
                std.debug.assert(std.mem.eql(u8, key, keystr));
                return mid;
            },
            1 => {
                std.debug.assert(!std.mem.eql(u8, key, keystr));
                log.debug("\"{s}\" >  \"{s}\" | {any} >  {any}", .{ key, keystr, key, keystr });
                low = mid + 1;
            },
            -1 => {
                std.debug.assert(!std.mem.eql(u8, key, keystr));
                log.debug("\"{s}\" <  \"{s}\" | {any} < {any}", .{ key, keystr, key, keystr });
                high = mid;
            },
            else => unreachable,
        }
    }

    var idx: isize = low + @as(isize, cmp);
    idx = clamp(isize, idx, 0, @intCast(cnt));
    return ~idx;
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    const signed = self.searchInsert(key);
    const idx: usize = b: switch (std.math.sign(signed)) {
        0, 1 => @abs(signed),
        -1 => {
            const i: usize = @intCast(~signed);
            std.debug.assert(i <= self.count());
            try self.insert(i, key, MapVal.Zero);
            break :b i;
        },
        else => unreachable,
    };

    return &self.vals.items[idx];
}

pub const MapEntry = struct {
    key: []const u8,
    val: *const MapVal,
};

pub const MapIterator = struct {
    map: *const BRCMap,
    idx: usize = 0,

    pub fn next(self: *MapIterator) ?MapEntry {
        if (self.idx >= self.map.keys.items.len) return null;

        const result: MapEntry = .{
            .key = self.map.getKeyString(self.map.keys.items[self.idx]),
            .val = &self.map.vals.items[self.idx],
        };

        self.idx += 1;
        return result;
    }
};

pub fn iterator(self: *const BRCMap) MapIterator {
    return MapIterator{
        .map = self,
        .idx = 0,
    };
}
