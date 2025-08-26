const builtin = @import("builtin");
const std = @import("std");

const StructSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8);
const MaxSmallSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8) - 1;
const MaxLargeSize: comptime_int = std.math.maxInt(u8);

const SizeCategory = enum(u8) {
    small = 1,
    medium = 2,
    large = 3,

    pub fn fromLen(len: usize) SizeCategory {
        const s: u8 = @intFromBool(len <= MaxSmallSize);
        const m: u8 = @intFromBool(len > MaxSmallSize and len <= MaxLargeSize);
        const l: u8 = @intFromBool(len > MaxLargeSize);

        const ei =
            (s * @intFromEnum(SizeCategory.small)) +
            (m * @intFromEnum(SizeCategory.medium)) +
            (l * @intFromEnum(SizeCategory.large));

        return @enumFromInt(ei);
    }
};

// TODO Handle strings longer than 255 (where the first byte of usize len is not guaranteed to be > 0)

const sso = @This();
data: [StructSize]u8 = undefined,

inline fn isSmall(self: *const sso) bool {
    return self.data[0] <= MaxSmallSize;
}
inline fn isMedium(self: *const sso) bool {
    return self.data[0] > MaxSmallSize;
}
inline fn isLarge(self: *const sso) bool {
    _ = &self;
    @panic("sso with length > 255 not yet implemented");
}

inline fn set_small(self: *sso, str: []const u8) void {
    const len_ptr: *u8 = &self.data[0];
    const data: []u8 = self.data[1..];
    std.debug.assert(str.len <= MaxSmallSize);
    len_ptr.* = @as(u8, @intCast(str.len));
    @memcpy(data[0..str.len], str);
}
inline fn set_medium(self: *sso, str: []const u8) void {
    std.debug.assert(str.len > MaxSmallSize);
    const len_ptr: *align(1) usize = @ptrCast(&self.data[0]);
    len_ptr.* = std.mem.nativeToLittle(usize, str.len);
    const ptr_ptr: *align(1) usize = @ptrCast(&self.data[@sizeOf(usize)]);
    ptr_ptr.* = @intFromPtr(str.ptr);
}
pub fn set(self: *sso, str: []const u8) void {
    switch (SizeCategory.fromLen(str.len)) {
        .small => self.set_small(str),
        .medium => self.set_medium(str),
        .large => @panic("sso with length > 255 not yet implemented"),
    }
}

inline fn get_small(self: *const sso) []const u8 {
    const len: u8 = self.data[0];
    const data = self.data[1..];
    std.debug.assert(len < StructSize);
    return data[0..len];
}
inline fn get_medium(self: *const sso) []const u8 {
    const len_ptr: *align(1) const usize = @ptrCast(&self.data[0]);
    const ptr_ptr: *align(1) const usize = @ptrCast(&self.data[@sizeOf(usize)]);
    var r: []u8 = undefined;
    r.len = std.mem.littleToNative(usize, len_ptr.*);
    r.ptr = @ptrFromInt(ptr_ptr.*);
    std.debug.assert(r.len > MaxSmallSize);
    return r;
}
pub fn get(self: *const sso) []const u8 {
    return switch (SizeCategory.fromLen(self.data[0])) {
        .small => self.get_small(),
        .medium => self.get_medium(),
        .large => @panic("sso with length > 255 not yet implemented"),
    };
}

pub fn clone(allocator: std.mem.Allocator, str: []const u8) !sso {
    var result: sso = .{};
    switch (SizeCategory.fromLen(str.len)) {
        .small => result.set_small(str),
        .medium => {
            const str_clone: []u8 = try allocator.alloc(u8, str.len);
            @memcpy(str_clone, str);
            result.set_medium(str_clone);
        },
        .large => @panic("sso with length > 255 not yet implemented"),
    }
    return result;
}

pub fn destroy(self: *sso, allocator: std.mem.Allocator) void {
    if (self.isMedium()) allocator.free(self.get_medium());
}

test set {
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');

    var string: sso = .{};
    while (iter.next()) |city| {
        string.set(city);
        if (city.len <= MaxSmallSize) {
            try std.testing.expect(string.isSmall());
            try std.testing.expect(!string.isMedium());
        } else {
            try std.testing.expect(!string.isSmall());
            try std.testing.expect(string.isMedium());
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
            try std.testing.expect(!string.isMedium());
        } else {
            try std.testing.expect(!string.isSmall());
            try std.testing.expect(string.isMedium());
        }
        try std.testing.expectEqualStrings(city, string.get());
    }
}
