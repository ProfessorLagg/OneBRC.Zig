const builtin = @import("builtin");
const std = @import("std");

comptime {
    if (@sizeOf(usize) > std.math.maxInt(u8)) unreachable;
}

inline fn memclone(comptime T: type, allocator: std.mem.Allocator, noalias mem: []const T) ![]T {
    const clone: []T = try allocator.alloc(T, mem.len);
    @memcpy(clone, mem);
    return clone;
}

/// 9 or 5 byte sso for 64-bit and 32-bit systems respectively.
/// 1 byte for length.
/// 8 or 4 bytes for data for 64-bit and 32-bit systems respectively.
/// Cannot store strings longer than 255 bytes
pub const sso9 = struct {
    data: usize = 0,
    len: u8 = 0,

    // Private functions
    inline fn isSmallLen(len: usize) bool {
        return len <= @sizeOf(usize);
    }
    inline fn isLargeLen(len: usize) bool {
        return len > @sizeOf(usize);
    }
    inline fn set_small(self: *sso9, str: []const u8) void {
        std.debug.assert(sso9.isSmallLen(str.len));
        const dataptr: *align(@alignOf(usize)) [@sizeOf(usize)]u8 = @ptrCast(&self.data);
        @memcpy(dataptr[0..str.len], str);
        self.len = @truncate(str.len);
    }
    inline fn set_large(self: *sso9, str: []const u8) void {
        std.debug.assert(sso9.isLargeLen(str.len));
        self.len = @truncate(str.len);
        self.data = @intFromPtr(str.ptr);
    }
    inline fn get_small(self: *const sso9) []const u8 {
        std.debug.assert(sso9.isSmallLen(self.len));
        const dataptr: *align(@alignOf(usize)) const [@sizeOf(usize)]u8 = @ptrCast(&self.data);
        return dataptr[0..self.len];
    }
    inline fn get_large(self: *const sso9) []const u8 {
        std.debug.assert(sso9.isLargeLen(self.len));
        const dataptr: [*]const u8 = @ptrFromInt(self.data);
        return dataptr[0..self.len];
    }

    // public functions
    pub inline fn empty(self: *const sso9) bool {
        return self.len == 0;
    }
    pub inline fn notEmpty(self: *const sso9) bool {
        return self.len > 0;
    }
    pub fn set(self: *sso9, str: []const u8) void {
        std.debug.assert(str.len <= std.math.maxInt(u8));
        if (sso9.isSmallLen(str.len)) self.set_small(str) else self.set_large(str);
    }
    pub fn get(self: *const sso9) []const u8 {
        return if (sso9.isSmallLen(self.len)) self.get_small() else self.get_large();
    }
    pub fn clone(allocator: std.mem.Allocator, str: []const u8) !sso9 {
        std.debug.assert(str.len <= std.math.maxInt(u8));
        var result: sso9 = .{};
        if (sso9.isSmallLen(str.len)) {
            result.set_small(str);
        } else {
            const str_clone: []u8 = try allocator.alloc(u8, str.len);
            @memcpy(str_clone, str);
            result.set_large(str_clone);
        }
        return result;
    }
    pub fn destroy(self: *sso9, allocator: std.mem.Allocator) void {
        if (sso9.isLargeLen(self.len)) allocator.free(self.get_large());
    }

    // Unit tests
    test "set_get" {
        const cities = @embedFile("cities.txt");
        var iter = std.mem.splitScalar(u8, cities, '\n');
        var str: sso9 = .{};
        while (iter.next()) |city| {
            str.set(city);
            try std.testing.expectEqual(sso9.isSmallLen(city.len), sso9.isSmallLen(str.len));
            try std.testing.expectEqual(sso9.isLargeLen(city.len), sso9.isLargeLen(str.len));
            try std.testing.expectEqualStrings(city, str.get());
        }
    }

    test clone {
        const allocator = std.testing.allocator;
        const cities = @embedFile("cities.txt");
        var iter = std.mem.splitScalar(u8, cities, '\n');

        var str: sso9 = .{};
        while (iter.next()) |city| {
            str = try sso9.clone(allocator, city);
            defer str.destroy(allocator);
            try std.testing.expectEqual(isSmallLen(city.len), isSmallLen(str.len));
            try std.testing.expectEqual(isLargeLen(city.len), isLargeLen(str.len));
            try std.testing.expectEqualStrings(city, str.get());
        }
    }
};

/// 16 or 8 byte sso for 64-bit and 32-bit systems respectively.
/// 8 or 4 bytes for data for 64-bit and 32-bit systems respectively.
/// Cannot store strings longer than 255 bytes
pub const sso16 = struct {
    const DataSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8);
    const MaxSmallLen: comptime_int = DataSize - 1;
    data: [DataSize]u8 = undefined,

    // Private functions
    inline fn isSmallLen(len: usize) bool {
        return len <= MaxSmallLen;
    }
    inline fn isLargeLen(len: usize) bool {
        return len > MaxSmallLen;
    }
    inline fn set_small(self: *sso16, str: []const u8) void {
        std.debug.assert(str.len <= MaxSmallLen);
        self.data[0] = @truncate(str.len);
        @memcpy(self.data[1..][0..str.len], str);
    }
    inline fn set_large(self: *sso16, str: []const u8) void {
        std.debug.assert(str.len > MaxSmallLen);
        const len_ptr: *align(1) usize = @ptrCast(&self.data[0]);
        const ptr_ptr: *align(1) usize = @ptrCast(&self.data[@sizeOf(usize)]);
        len_ptr.* = std.mem.nativeToLittle(usize, str.len);
        ptr_ptr.* = @intFromPtr(str.ptr);
    }
    inline fn get_small(self: *const sso16) []const u8 {
        std.debug.assert(self.data[0] < DataSize);
        return self.data[1..][0..self.data[0]];
    }
    inline fn get_large(self: *const sso16) []const u8 {
        const len_ptr: *align(1) const usize = @ptrCast(&self.data[0]);
        const ptr_ptr: *align(1) const usize = @ptrCast(&self.data[@sizeOf(usize)]);
        const len: usize = std.mem.littleToNative(usize, len_ptr.*);
        const ptr: [*]align(1) const u8 = @ptrFromInt(ptr_ptr.*);
        std.debug.assert(len_ptr.* > MaxSmallLen);
        return ptr[0..len];
    }

    // Public functions
    pub inline fn empty(self: *const sso16) bool {
        return self.data[0] == 0;
    }
    pub inline fn notEmpty(self: *const sso16) bool {
        return self.data[0] > 0;
    }
    pub fn set(self: *sso16, str: []const u8) void {
        std.debug.assert(str.len <= std.math.maxInt(u8));
        if (sso16.isSmallLen(str.len)) self.set_small(str) else self.set_large(str);
    }
    pub fn initFrom(str: []const u8) sso16 {
        var r: sso16 = .{};
        r.set(str);
        return r;
    }
    pub fn get(self: *const sso16) []const u8 {
        return if (sso16.isSmallLen(self.data[0])) self.get_small() else self.get_large();
    }
    pub fn clone(allocator: std.mem.Allocator, str: []const u8) !sso16 {
        std.debug.assert(str.len <= std.math.maxInt(u8));
        return if (isLargeLen(str.len)) sso16.initFrom(try memclone(u8, allocator, str)) else sso16.initFrom(str);
    }
    pub fn free(self: *sso16, allocator: std.mem.Allocator) void {
        if (isLargeLen(self.data[0])) allocator.free(self.get_large());
    }
    // Unit tests
    test "set_get" {
        const cities = @embedFile("cities.txt");
        var iter = std.mem.splitScalar(u8, cities, '\n');
        var str: sso16 = .{};
        while (iter.next()) |city| {
            str.set(city);
            try std.testing.expectEqual(sso16.isSmallLen(city.len), sso16.isSmallLen(str.data[0]));
            try std.testing.expectEqual(sso16.isLargeLen(city.len), sso16.isLargeLen(str.data[0]));
            try std.testing.expectEqualStrings(city, str.get());
        }
    }

    test clone {
        const allocator = std.testing.allocator;
        const cities = @embedFile("cities.txt");
        var iter = std.mem.splitScalar(u8, cities, '\n');

        var str: sso16 = .{};
        while (iter.next()) |city| {
            str = try sso16.clone(allocator, city);
            defer str.free(allocator);
            try std.testing.expectEqual(isSmallLen(city.len), isSmallLen(str.data[0]));
            try std.testing.expectEqual(isLargeLen(city.len), isLargeLen(str.data[0]));
            try std.testing.expectEqualStrings(city, str.get());
        }
    }
};

test sso9 {
    _ = sso9;
}

test sso16 {
    _ = sso16;
}
