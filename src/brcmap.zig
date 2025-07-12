const builtin = @import("builtin");
const std = @import("std");
const DynamicBuffer = @import("DynamicBuffer.zig");

fn compare_from_bools(lt: bool, gt: bool) i8 {
    const lti: i8 = @intFromBool(lt); // 11 if true, 0 if false
    const gti: i8 = @intFromBool(gt); // 1 if true, 0 if false
    return (0 - gti) + lti;
}

fn compare_strings(a: []const u8, b: []const u8) i8 {
    var cmp: i8 = compare_from_bools(a.len < b.len, a.len > b.len);
    if (cmp != 0) return cmp;

    const l: usize = @min(a.len, b.len);
    var i: usize = 0;
    while (i < l and cmp == 0) : (i += 1) {
        cmp = compare_from_bools(a[i] < b[i], a[i] > b[i]);
    }
    return cmp;
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

fn insert(self: *BRCMap, idx: usize, key: []const u8, val: MapVal) !void {
    const new_string = try self.stringBuffer.write(key);
    const new_left: usize = @intCast(@intFromPtr(new_string.ptr) - @intFromPtr(self.stringBuffer.raw.ptr));
    const new_offset = KeyOffset.init(
        @truncate(new_string.len),
        @truncate(new_left),
    );
    try self.keys.insert(idx, new_offset);
    try self.vals.insert(idx, val);
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

fn linearSearch(self: *const BRCMap, key: []const u8) ?usize {
    for (0..self.keys.items.len) |i| {
        const keystr = self.getKeyString(self.keys.items[i]);
        if (std.mem.eql(u8, key, keystr)) return i;
    }
    return null;
}

fn countInstances(self: *const BRCMap, key: []const u8) usize {
    var r: usize = 0;
    for (0..self.keys.items.len) |i| {
        const keystr = self.getKeyString(self.keys.items[i]);
        r += @intFromBool(std.mem.eql(u8, key, keystr));
    }
    return r;
}

pub fn findOrInsert_0(self: *BRCMap, key: []const u8) !*MapVal {
    if (self.keys.items.len == 0) {
        try self.insert(0, key, MapVal.Zero);
        return &self.vals.items[0];
    }

    var left: usize = 0;
    var right: usize = self.keys.items.len;
    var mid: usize = 0;
    var cmp: i8 = 1;
    while (cmp != 0 and left != right) {
        mid = left + @divFloor(right - left, 2);
        const keystr: []const u8 = self.getKeyString(self.keys.items[mid]);
        cmp = compare_strings(key, keystr);
        switch (cmp) {
            0 => return &self.vals.items[mid],
            -1 => right = mid,
            1 => left = mid + 1,
            else => unreachable,
        }
    }

    if (cmp != 0) {
        if (mid < self.keys.items.len) {
            try self.insert(mid, key, MapVal.Zero);
        } else {
            try self.append(key, MapVal.Zero);
            mid = self.keys.items.len - 1;
        }
        //std.fmt.format(stdout, "\tinserted key at: {d}\n", .{mid}) catch unreachable;
    } else {
        //std.fmt.format(stdout, "\tfound key at: {d}\n", .{mid}) catch unreachable;
    }

    //std.debug.assert(self.countInstances(key) == 1);
    std.debug.assert(std.mem.eql(u8, key, self.getKeyString(self.keys.items[mid])));
    return &self.vals.items[mid];
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    if (self.keys.items.len == 0) {
        try self.insert(0, key, MapVal.Zero);
        return &self.vals.items[0];
    }

    if (self.indexOf(key)) |idx| return &self.vals.items[idx];

    var i: usize = 0;
    var cmp: i8 = -1;
    while (i < self.keys.items.len) : (i += 1) {
        const keystr: []const u8 = self.getKeyString(self.keys.items[i]);
        cmp = compare_strings(key, keystr);
        switch (cmp) {
            0 => return &self.vals.items[i],
            -1 => {},
            1 => {
                try self.insert(i, key, MapVal.Zero);
                return &self.vals.items[i];
            },
            else => unreachable,
        }
    }
    std.debug.assert(cmp == -1);
    try self.append(key, MapVal.Zero);
    return &self.vals.items[self.vals.items.len - 1];
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
