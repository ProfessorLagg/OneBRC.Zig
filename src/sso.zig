const builtin = @import("builtin");
const std = @import("std");

const StructSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8);
const MaxSmallSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8) - 1;

const sso = @This();
data: [StructSize]u8 = undefined,

inline fn isSmall(self: *const sso) bool {
    return self.data[0] <= MaxSmallSize;
}
inline fn isLarge(self: *const sso) bool {
    return self.data[0] > MaxSmallSize;
}

inline fn set_small(self: *sso, str: []const u8) void {
    std.debug.assert(str.len <= std.math.maxInt(u8));
    const len_ptr: *u8 = &self.data[0];
    const data: []u8 = self.data[1..];
    std.debug.assert(str.len <= MaxSmallSize);
    len_ptr.* = @as(u8, @intCast(str.len));
    @memcpy(data[0..str.len], str);
}
inline fn set_large(self: *sso, str: []const u8) void {
    std.debug.assert(str.len > MaxSmallSize);
    std.debug.assert(str.len <= std.math.maxInt(u8));
    const len_ptr: *align(1) usize = @ptrCast(&self.data[0]);
    len_ptr.* = std.mem.nativeToLittle(usize, str.len);
    const ptr_ptr: *align(1) usize = @ptrCast(&self.data[@sizeOf(usize)]);
    ptr_ptr.* = @intFromPtr(str.ptr);
}
pub fn set(self: *sso, str: []const u8) void {
    std.debug.assert(str.len <= std.math.maxInt(u8));
    if (str.len <= MaxSmallSize) self.set_small(str) else self.set_large(str);
}

inline fn get_small(self: *const sso) []const u8 {
    const len: u8 = self.data[0];
    const data = self.data[1..];
    std.debug.assert(len < StructSize);
    return data[0..len];
}
inline fn get_large(self: *const sso) []const u8 {
    const len_ptr: *align(1) const usize = @ptrCast(&self.data[0]);
    const ptr_ptr: *align(1) const usize = @ptrCast(&self.data[@sizeOf(usize)]);
    var r: []u8 = undefined;
    r.len = std.mem.littleToNative(usize, len_ptr.*);
    r.ptr = @ptrFromInt(ptr_ptr.*);
    std.debug.assert(r.len > MaxSmallSize);
    return r;
}
pub fn get(self: *const sso) []const u8 {
    return if (self.isSmall()) self.get_small() else self.get_large();
}

pub fn clone(allocator: std.mem.Allocator, str: []const u8) !sso {
    var result: sso = .{};
    if (str.len <= MaxSmallSize) {
        result.set_small(str);
    } else {
        const str_clone: []u8 = try allocator.alloc(u8, str.len);
        @memcpy(str_clone, str);
        result.set_large(str_clone);
    }
    return result;
}

pub fn destroy(self: *sso, allocator: std.mem.Allocator) void {
    if (self.isLarge()) allocator.free(self.get_large());
}

test set {
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');

    var string: sso = .{};
    while (iter.next()) |city| {
        string.set(city);
        if (city.len <= MaxSmallSize) {
            try std.testing.expect(string.isSmall());
            try std.testing.expect(!string.isLarge());
        } else {
            try std.testing.expect(!string.isSmall());
            try std.testing.expect(string.isLarge());
        }

        try std.testing.expectEqualStrings(city, string.get());
    }
}

test clone {
    const allocator = std.testing.allocator;
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');

    var string: sso = .{};
    while (iter.next()) |city| {
        string = try sso.clone(allocator, city);
        defer string.destroy(allocator);
        if (city.len <= MaxSmallSize) {
            try std.testing.expect(string.isSmall());
            try std.testing.expect(!string.isLarge());
        } else {
            try std.testing.expect(!string.isSmall());
            try std.testing.expect(string.isLarge());
        }
        try std.testing.expectEqualStrings(city, string.get());
    }
}
