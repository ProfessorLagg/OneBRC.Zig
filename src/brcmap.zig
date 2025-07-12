const builtin = @import("builtin");
const std = @import("std");
const DynamicBuffer = @import("DynamicBuffer.zig");

fn compare_strings(a: []const u8, b: []const u8) i8 {
    const l: usize = @min(a.len, b.len);

    // TODO Use usize cmp when strings are long enough
    // TODO Vectorize this when they strings are long enough
    var i: usize = 0;
    var c: i8 = 0;
    while (i < l and c != 0) : (i += 1) {
        const lt: i8 = @intFromBool(a[i] < b[i]) * @as(i8, -1);
        const gt: i8 = @intFromBool(a[i] > b[i]);
        c = lt + gt;
    }

    return std.math.sign(c);
}

fn compare_strings_order(a: []const u8, b: []const u8) std.math.Order {
    return switch (compare_strings(a, b)) {
        -1 => .lt,
        0 => .eq,
        1 => .gt,
        else => unreachable,
    };
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

    sum: i32 = 0,
    count: i32 = 0,

    pub inline fn add(self: *MapVal, v: i32) void {
        self.sum += v;
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

inline fn getKeyString(self: *const BRCMap, offset: KeyOffset) []const u8 {
    const L: usize = offset.left();
    const R: usize = offset.right();
    std.debug.assert(R <= self.stringBuffer.used.len);
    return self.stringBuffer.used[L..R];
}

fn sort(self: *BRCMap) void {
    const Ks = self.keys.items;
    const Vs = self.vals.items;
    std.debug.assert(Ks.len == Vs.len);

    var i: usize = 1;
    while (i < Ks.len) : (i += 1) {
        const ko: KeyOffset = Ks[i];
        const ks: []const u8 = self.getKeyString(ko);
        const v: MapVal = Vs[i];
        var j: usize = i;
        while (j > 0 and (compare_strings(self.getKeyString(Ks[j - 1]), ks) == 1)) : (j -= 1) {
            Ks[j] = Ks[j - 1];
            Vs[j] = Vs[j - 1];
        }
        Ks[j] = ko;
        Vs[j] = v;
    }
}

fn add(self: *BRCMap, key: []const u8, val: MapVal) !void {
    std.debug.assert(self.indexOf(key) == null);
    const keystr = try self.stringBuffer.write(key);
    const offset: usize = @intFromPtr(keystr.ptr) - @intFromPtr(self.stringBuffer.raw.ptr);
    try self.keys.append(KeyOffset.init(@truncate(keystr.len), @truncate(offset)));
    try self.vals.append(val);
    self.sort();
}

inline fn addKey(self: *BRCMap, key: []const u8) !void {
    try self.add(key, MapVal.Zero);
}

fn indexOf(self: *const BRCMap, key: []const u8) ?usize {
    // TODO Use Binary search here
    const Ks = self.keys.items[0..];
    for (Ks, 0..Ks.len) |ko, i| {
        const ks: []const u8 = self.getKeyString(ko);
        if (std.mem.eql(u8, key, ks)) return i;
    }

    return null;
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    if (self.indexOf(key)) |idx| {
        return &self.vals.items[idx];
    } else {
        try self.addKey(key);
        const idx = self.indexOf(key) orelse unreachable;
        return &self.vals.items[idx];
    }
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
