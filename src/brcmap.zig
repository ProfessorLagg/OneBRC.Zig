const builtin = @import("builtin");
const std = @import("std");
const ut = @import("utils.zig");
const Order = std.math.Order;
const DynamicBuffer = @import("DynamicBuffer.zig");
const DynamicArray = @import("DynamicArray.zig").DynamicArray;

const log = std.log.scoped(.BRCMap);

inline fn indexOfDiff(a: []const u8, b: []const u8) ?usize {
    const l: usize = @min(a.len, b.len);
    for (0..l) |i| {
        if (a[i] != b[i]) return i;
    }
    return null;
}
inline fn compare_from_bools(lessThan: bool, greaterThan: bool) i8 {
    std.debug.assert((lessThan and greaterThan) != true);
    const lt: i8 = @intFromBool(lessThan); // 1 if true, 0 if false
    const gt: i8 = @intFromBool(greaterThan); // 1 if true, 0 if false
    // case gt = 0, lt = 1 => 0 - 1 == -1
    // case gt = 1, lt = 0 => 1 - 0 == 1
    // case gt = 0, lt = 0 => 0 - 0 == 0
    return gt - lt;
}
fn compare_from_bools_order(lt: bool, gt: bool) Order {
    return switch (compare_from_bools(lt, gt)) {
        -1 => .lt,
        0 => .eq,
        1 => .gt,
        else => unreachable,
    };
}
fn compare_string(a: []const u8, b: []const u8) i8 {
    const l: usize = @min(a.len, b.len);
    var i: usize = 0;
    var c: i8 = 0;
    while (i < l and c == 0) : (i += 1) {
        c = compare_from_bools(a[i] < b[i], a[i] > b[i]);
    }
    if (c != 0) return c;
    return compare_from_bools(a.len < b.len, a.len > b.len);
}
fn compare_string_order(a: []const u8, b: []const u8) Order {
    return switch (compare_string(a, b)) {
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
// const OffsetList = std.ArrayList(KeyOffset);
const OffsetList = DynamicArray(KeyOffset);

pub const MapVal = struct {
    pub const Zero: MapVal = .{ .sum = 0, .count = 0 };

    // TODO MISSING MIN AND MAX
    sum: i48 = 0,
    count: i32 = 0,

    pub inline fn add(self: *MapVal, v: i48) void {
        self.sum += v;
        self.count += 1;
    }

    pub inline fn mean(self: *const MapVal) f64 {
        const sum_f: f64 = @floatFromInt(self.sum);
        const cnt_f: f64 = @floatFromInt(self.count);
        return sum_f / cnt_f;
    }
};
const MapValList = DynamicArray(MapVal);

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
pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !BRCMap {
    var r: BRCMap = try BRCMap.init(allocator);
    if (capacity > 0) {
        try r.keys.ensureCapacity(capacity);
        try r.vals.ensureCapacity(capacity);
    }
    return r;
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
    return compare_string_order(key, str);
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

    ut.debug.print("inserted key \"{s}\" | {any} into position: {d}", .{ self.getKeyString(new_offset), self.getKeyString(new_offset), idx });
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
        cmp = compare_string(key, keystr);
        switch (cmp) {
            0 => return mid,
            -1 => right = mid,
            1 => left = mid + 1,
            else => unreachable,
        }
    }
    return null;
}

fn binarySearch(self: *const BRCMap, item: []const u8) ?usize {
    ut.debug.print("\nbinary searching for key: \"{s}\"\n", .{item});

    var L: isize = 0;
    var R: isize = @as(isize, @intCast(self.count())) - 1;
    while (L <= R) {
        const m: isize = L + @divFloor(R - L, 2);
        const k = self.getKeyString(self.keys.items[@abs(m)]);
        const c: i8 = compare_string(k, item);
        switch (c) {
            0 => {
                ut.debug.print("\tk{d}: \"{s}\" == key: \"{s}\"\n", .{ m, k, item });
                return @abs(m);
            },
            1 => {
                ut.debug.print("\tk{d}: \"{s}\" <  key: \"{s}\"\n", .{ m, k, item });
                L = m + 1;
            },
            -1 => {
                ut.debug.print("\tk{d}: \"{s}\" >  key: \"{s}\"\n", .{ m, k, item });
                R = m - 1;
            },
            else => unreachable,
        }
    }
    return null;
}

fn searchInsert(self: *const BRCMap, item: []const u8) isize {
    ut.debug.print("\nbinary searching for key: \"{s}\"\n", .{item});

    var L: isize = 0;
    var R: isize = @as(isize, @intCast(self.count())) - 1;
    var m: isize = 0;
    while (L <= R) {
        m = L + @divFloor(R - L, 2);
        const k = self.getKeyString(self.keys.items[@abs(m)]);
        const c: i8 = compare_string(k, item);
        switch (c) {
            0 => {
                ut.debug.print("\tk{d}: \"{s}\" == key: \"{s}\"\n", .{ m, k, item });
                return m;
            },
            1 => {
                ut.debug.print("\tk{d}: \"{s}\" <  key: \"{s}\"\n", .{ m, k, item });
                L = m + 1;
            },
            -1 => {
                ut.debug.print("\tk{d}: \"{s}\" >  key: \"{s}\"\n", .{ m, k, item });
                R = m - 1;
            },
            else => unreachable,
        }
    }

    m = L;
    while (m < self.count()) : (m += 1) {
        const k = self.getKeyString(self.keys.items[@abs(m)]);
        const cmp = compare_string(item, k);
        switch (cmp) {
            0 => {
                ut.debug.print("Keys:\n", .{});
                for (0..self.count()) |j| {
                    const keystr = self.getKeyString(self.keys.items[j]);
                    ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keystr });
                }
                std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ item, m });
                @panic("Binary Search Failed to find key!");
            },
            1 => break,
            -1 => continue,
            else => unreachable,
        }
    }

    return ~m;
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    const cnt = self.count();
    if (cnt == 0) {
        try self.append(key, MapVal.Zero);
        return &self.vals.items[0];
    }
    // const bsr = self.binarySearch(key);
    // if (bsr != null) {
    //     return &self.vals.items[bsr.?];
    // }

    // // TODO REMOVE THIS LINEAR SEARCH. IT IS ONLY HERE FOR DEBUG
    // var i: usize = 0;
    // while (i < cnt) : (i += 1) {
    //     const cmp = compare_string(key, self.getKeyString(self.keys.items[i]));
    //     switch (cmp) {
    //         0 => {
    //             ut.debug.print("Keys:\n", .{});
    //             for (0..self.count()) |j| {
    //                 const keystr = self.getKeyString(self.keys.items[j]);
    //                 ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keystr });
    //             }
    //             std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ key, i });
    //             @panic("Binary Search Failed to find key!");
    //         },
    //         1 => break,
    //         -1 => continue,
    //         else => unreachable,
    //     }
    // }
    // std.debug.assert(i <= self.count());
    // try self.insert(i, key, MapVal.Zero);
    // return &self.vals.items[i];

    const signed = self.searchInsert(key);
    const idx: usize = b: switch (std.math.sign(signed)) {
        0, 1 => @abs(signed),
        -1 => {
            const c = self.count();
            const i: usize = @intCast(~signed);
            std.debug.assert(i <= c);
            std.debug.assert(i == c or !ut.mem.eqlBytes(key, self.getKeyString(self.keys.items[i])));
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
