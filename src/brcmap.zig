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
    // case gt = 0, lt = 1 => 0 - 1 == -1
    // case gt = 1, lt = 0 => 1 - 0 == 1
    // case gt = 0, lt = 0 => 0 - 0 == 0
    return @as(i8, @intFromBool(greaterThan)) - @as(i8, @intFromBool(lessThan));
}
inline fn compare_string_v0(a: []const u8, b: []const u8) i8 {
    const l: usize = @min(a.len, b.len);
    var i: usize = 0;
    var c: i8 = 0;
    while (i < l and c == 0) : (i += 1) c = compare_from_bools(a[i] < b[i], a[i] > b[i]);
    if (c != 0) return c;
    return compare_from_bools(a.len < b.len, a.len > b.len);
}

fn index_of_diff(a: [*]const u8, b: [*]const u8, l: usize) ?usize {
    var s: usize = 0; // Index of where not yet compared bytes start
    ol: while (s < l) {
        // TODO Use Log2 floor + switch instead of if statements
        const rem: usize = (l - 1) - s; // Remaining length
        if (rem >= @sizeOf(u64)) {
            const aptr: *const [@sizeOf(u64)]u8 = @ptrCast(&a[s]);
            const bptr: *const [@sizeOf(u64)]u8 = @ptrCast(&b[s]);
            const d64: u64 = @as(u64, @bitCast(aptr.*)) ^ @as(u64, @bitCast(bptr.*));
            const d: [@sizeOf(u64)]u8 = std.mem.toBytes(d64);
            ut.debug.print("index_of_diff u64 \"{s}\", \"{s}\" = {any}\n", .{ a[s .. s + @sizeOf(u64)], b[s .. s + @sizeOf(u64)], d });
            for (0..@sizeOf(u64)) |i| if (d[i] != 0) return i + s;
            s += @sizeOf(u64);
            continue :ol;
        }
        if (rem >= @sizeOf(u32)) {
            // u32 compare
            const aptr: *const [@sizeOf(u32)]u8 = @ptrCast(&a[s]);
            const bptr: *const [@sizeOf(u32)]u8 = @ptrCast(&b[s]);
            const d32: u32 = @as(u32, @bitCast(aptr.*)) ^ @as(u32, @bitCast(bptr.*));
            const d: [@sizeOf(u32)]u8 = std.mem.toBytes(d32);
            ut.debug.print("index_of_diff u32 \"{s}\", \"{s}\" = {any}\n", .{ a[s .. s + @sizeOf(u32)], b[s .. s + @sizeOf(u32)], d });
            for (0..@sizeOf(u32)) |i| if (d[i] != 0) return i + s;
            s += @sizeOf(u32);
            continue :ol;
        }
        if (rem >= @sizeOf(u16)) {
            // u16 compare
            const aptr: *const [@sizeOf(u16)]u8 = @ptrCast(&a[s]);
            const bptr: *const [@sizeOf(u16)]u8 = @ptrCast(&b[s]);
            const d16: u16 = @as(u16, @bitCast(aptr.*)) ^ @as(u16, @bitCast(bptr.*));
            const d: [@sizeOf(u16)]u8 = std.mem.toBytes(d16);
            ut.debug.print("index_of_diff u16 \"{s}\", \"{s}\" = {any}\n", .{ a[s .. s + @sizeOf(u16)], b[s .. s + @sizeOf(u16)], d });
            for (0..@sizeOf(u16)) |i| if (d[i] != 0) return i + s;
            s += @sizeOf(u16);
            continue :ol;
        }

        if (a[s] != b[s]) return s;
        s += 1;
    }
    return null;
}

fn compare_string(a: []const u8, b: []const u8) i8 {
    if (index_of_diff(a.ptr, b.ptr, @min(a.len, b.len))) |idx| {
        ut.debug.print("found diff between \"{s}\" <-> \"{s}\" at index {d} = '{c}'(\\x{x}) != '{c}' (\\x{x}) \n", .{ a, b, idx, a[idx], a[idx], b[idx], b[idx] });
        return compare_from_bools(a[idx] < b[idx], a[idx] > b[idx]);
    }
    return compare_from_bools(a.len < b.len, a.len > b.len);
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
        self.sum += v;
        self.count += 1;
        const v16: i16 = @intCast(v);
        self.min = @min(self.min, v16);
        self.max = @max(self.max, v16);
    }

    pub inline fn finalize(self: *const MapVal) FinalMapVal {
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
            -1 => {
                ut.debug.print("\tk{d}: \"{s}\" <  key: \"{s}\"\n", .{ m, k, item });
                R = m - 1;
            },
            1 => {
                ut.debug.print("\tk{d}: \"{s}\" >  key: \"{s}\"\n", .{ m, k, item });
                L = m + 1;
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
                if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                    ut.debug.print("Keys:\n", .{});
                    for (0..self.count()) |j| {
                        const keystr = self.getKeyString(self.keys.items[j]);
                        ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keystr });
                    }
                    std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ item, m });
                } else @panic("Binary Search Failed to find key!");
            },
            1 => break,
            -1 => continue,
            else => unreachable,
        }
    }

    return ~m;
}

fn searchInsert_v1(self: *const BRCMap, item: []const u8) isize {
    ut.debug.print("\nbinary searching for key: \"{s}\"\n", .{item});

    std.debug.assert(self.count() > 0);

    var L: isize = 0;
    var R: isize = @as(isize, @intCast(self.count())) - 1;

    var m: isize = L + @divFloor(R - L, 2);
    var k: []const u8 = self.getKeyString(self.keys.items[@abs(m)]);
    var c: i8 = compare_string(k, item);
    loop: switch (c) {
        0 => return m,
        -1 => {
            ut.debug.print("\tk{d}: \"{s}\" <  key: \"{s}\"\n", .{ m, k, item });
            R = m - 1;
            if (L > R) break :loop;

            m = L + @divFloor(R - L, 2);
            k = self.getKeyString(self.keys.items[@abs(m)]);
            c = compare_string(k, item);
            continue :loop c;
        },
        1 => {
            ut.debug.print("\tk{d}: \"{s}\" >  key: \"{s}\"\n", .{ m, k, item });
            L = m + 1;
            if (L > R) break :loop;

            m = L + @divFloor(R - L, 2);
            k = self.getKeyString(self.keys.items[@abs(m)]);
            c = compare_string(k, item);
            continue :loop c;
        },
        else => unreachable,
    }

    m = L;
    while (m < self.count()) : (m += 1) {
        k = self.getKeyString(self.keys.items[@abs(m)]);
        c = compare_string(item, k);
        switch (c) {
            0 => {
                if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                    ut.debug.print("Keys:\n", .{});
                    for (0..self.count()) |j| {
                        const keystr = self.getKeyString(self.keys.items[j]);
                        ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keystr });
                    }
                    std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ item, m });
                } else @panic("Binary Search Failed to find key!");
            },
            1 => break,
            -1 => continue,
            else => unreachable,
        }
    }

    return ~m;
}

fn findOrInsert_real(self: *BRCMap, key: []const u8) !*MapVal {
    const cnt = self.count();
    if (cnt == 0) {
        try self.append(key, MapVal.None);
        return &self.vals.items[0];
    }
    const signed = self.searchInsert(key);
    const idx: usize = b: switch (std.math.sign(signed)) {
        0, 1 => @abs(signed),
        -1 => {
            const c = self.count();
            const i: usize = @intCast(~signed);
            std.debug.assert(i <= c);
            std.debug.assert(i == c or !ut.mem.eqlBytes(key, self.getKeyString(self.keys.items[i])));
            try self.insert(i, key, MapVal.None);
            break :b i;
        },
        else => unreachable,
    };
    return &self.vals.items[idx];
}

fn findOrInsert_debug(self: *BRCMap, key: []const u8) !*MapVal {
    const cnt = self.count();
    if (cnt == 0) {
        try self.append(key, MapVal.None);
        return &self.vals.items[0];
    }
    const bsr = self.binarySearch(key);
    if (bsr != null) {
        return &self.vals.items[bsr.?];
    }

    // TODO REMOVE THIS LINEAR SEARCH. IT IS ONLY HERE FOR DEBUG
    var i: usize = 0;
    while (i < cnt) : (i += 1) {
        const cmp = compare_string(key, self.getKeyString(self.keys.items[i]));
        switch (cmp) {
            0 => {
                ut.debug.print("Keys:\n", .{});
                for (0..self.count()) |j| {
                    const keystr = self.getKeyString(self.keys.items[j]);
                    ut.debug.print("\t{d:>5}: \"{s}\"\n", .{ j, keystr });
                }
                std.debug.panic("Binary Search Failed to find key \"{s}\" at index {d}", .{ key, i });
                @panic("Binary Search Failed to find key!");
            },
            1 => break,
            -1 => continue,
            else => unreachable,
        }
    }
    std.debug.assert(i <= self.count());
    try self.insert(i, key, MapVal.None);
    return &self.vals.items[i];
}

pub fn findOrInsert(self: *BRCMap, key: []const u8) !*MapVal {
    return self.findOrInsert_debug(key);
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
