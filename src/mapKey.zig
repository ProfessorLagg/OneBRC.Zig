const std = @import("std");
const sorted = @import("sorted/sorted.zig");
pub const MapKey = @This();

pub inline fn sumString(str: []const u8) u8 {
    var sum: u8 = str[0];
    for (1..str.len) |i| {
        sum +%= str[i];
    }
    return sum;
}
const bufferlen: usize = 100;
buffer: [bufferlen]u8 = undefined,
len: u8 = 0,
sum: u8 = 0,

pub inline fn create(str: []const u8) MapKey {
    var r: MapKey = .{};
    r.set(str);
    return r;
}

pub inline fn set(self: *MapKey, str: []const u8) void {
    std.debug.assert(str.len <= bufferlen);
    std.mem.copyForwards(u8, &self.buffer, str);
    self.len = @as(u8, @intCast(str.len));
    self.sum = sumString(str);
}

/// Returns the key as a string
pub inline fn toString(self: *const MapKey) []const u8 {
    return self.buffer[0..self.len];
}

pub inline fn compare_valid(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
    const len = @max(a.len, b.len);
    for (0..len) |i| {
        const cmp_char = sorted.compareNumber(a.buffer[i], b.buffer[i]);
        if (cmp_char != .Equal) {
            return cmp_char;
        }
    }
    return .Equal;
}

pub fn compare(a: *const MapKey, b: *const MapKey) sorted.CompareResult {
    var cmp = sorted.compareNumber(a.sum, b.sum);
    if (cmp != .Equal) {
        return cmp;
    }
    cmp = sorted.compareNumber(a.len, b.len);
    if (cmp != .Equal) {
        return cmp;
    }

    for (0..a.len) |i| {
        cmp = sorted.compareNumber(a.buffer[i], b.buffer[i]);
        if (cmp != .Equal) {
            return cmp;
        }
    }
    return .Equal;
}
