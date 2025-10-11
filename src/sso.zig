const builtin = @import("builtin");
const std = @import("std");
const memeql = @import("root.zig").eqlBytes;

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
};

test "sso9.set_get" {
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');
    var str: sso9 = .{};
    var sCount: usize = 0;
    var lCount: usize = 0;
    while (iter.next()) |city| {
        str.set(city);
        sCount += @intFromBool(sso9.isSmallLen(city.len));
        lCount += @intFromBool(sso9.isLargeLen(city.len));
        try std.testing.expectEqual(sso9.isSmallLen(city.len), sso9.isSmallLen(str.len));
        try std.testing.expectEqual(sso9.isLargeLen(city.len), sso9.isLargeLen(str.len));
        try std.testing.expectEqualStrings(city, str.get());
    }

    try std.testing.expect(sCount > 0);
    try std.testing.expect(lCount > 0);
}
test "sso9.clone" {
    const allocator = std.testing.allocator;
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');

    var str: sso9 = .{};
    while (iter.next()) |city| {
        str = try sso9.clone(allocator, city);
        defer str.destroy(allocator);
        try std.testing.expectEqual(sso9.isSmallLen(city.len), sso9.isSmallLen(str.len));
        try std.testing.expectEqual(sso9.isLargeLen(city.len), sso9.isLargeLen(str.len));
        try std.testing.expectEqualStrings(city, str.get());
    }
}

/// 16 or 8 byte sso for 64-bit and 32-bit systems respectively.
/// 8 or 4 bytes for data for 64-bit and 32-bit systems respectively.
/// Cannot store strings longer than 255 bytes
pub const sso16 = struct {
    const DataSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8);
    const TVec: type = @Vector(DataSize, u8);
    const DataAlign: comptime_int = @alignOf(TVec);
    const MaxSmallLen: comptime_int = DataSize - 1;
    data: TVec = @splat(0),

    // Private functions
    pub inline fn isSmallLen(len: usize) bool {
        return len <= MaxSmallLen;
    }
    pub inline fn isLargeLen(len: usize) bool {
        return len > MaxSmallLen;
    }
    inline fn set_small(self: *sso16, str: []const u8) void {
        std.debug.assert(str.len <= MaxSmallLen);
        const dataptr: *align(DataAlign) [DataSize]u8 = @ptrCast(&self.data);
        dataptr[0] = @truncate(str.len);
        @memcpy(dataptr[1..][0..str.len], str);
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
        const dataptr: *align(DataAlign) const [DataSize]u8 = @ptrCast(&self.data);
        return dataptr[1..][0..dataptr[0]];
    }
    inline fn get_large(self: *const sso16) []const u8 {
        const len_ptr: *align(1) const usize = @ptrCast(&self.data[0]);
        const ptr_ptr: *align(1) const usize = @ptrCast(&self.data[@sizeOf(usize)]);
        const len: usize = std.mem.littleToNative(usize, len_ptr.*);
        const ptr: [*]align(1) const u8 = @ptrFromInt(ptr_ptr.*);
        std.debug.assert(len_ptr.* > MaxSmallLen);
        return ptr[0..len];
    }
    inline fn eql_small(a: *const sso16, b: *const sso16) bool {
        std.debug.assert(isSmallLen(a.data[0]));
        std.debug.assert(isSmallLen(b.data[0]));
        return @reduce(.And, a.data == b.data);
    }
    inline fn eql_large(a: *const sso16, b: *const sso16) bool {
        std.debug.assert(isLargeLen(a.data[0]));
        std.debug.assert(isLargeLen(b.data[0]));
        return memeql(a.get_large(), b.get_large());
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
    pub fn eql(a: *const sso16, b: *const sso16) bool {
        // 0: both are small, 1: one is small the other is large, 2: both are large
        const magicnumber: u8 = asm volatile ( // NO FOLD
                \\ cmp $15, %al
                \\ setg %al
                \\ and $1, %al
                \\ cmp $15, %bl
                \\ setg %bl
                \\ and $1, %bl
                \\ add %bl, %al
                : [ret] "={al}" (-> u8),
                : [a] "{al}" (a.data[0]),
                  [b] "{bl}" (b.data[0]),
            );
        return switch (magicnumber) {
            0 => eql_small(a, b),
            1 => false,
            2 => eql_large(a, b),
            else => unreachable,
        };
    }
    pub fn isSmall(self: *sso16) bool {
        return sso16.isSmallLen(self.data[0]);
    }
    pub fn isLarge(self: *sso16) bool {
        return !self.isSmall();
    }
};

test "sso16.set_get" {
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');
    var str: sso16 = .{};
    var sCount: usize = 0;
    var lCount: usize = 0;
    while (iter.next()) |city| {
        str.set(city);
        sCount += @intFromBool(sso16.isSmallLen(city.len));
        lCount += @intFromBool(sso16.isLargeLen(city.len));
        try std.testing.expectEqual(sso16.isSmallLen(city.len), sso16.isSmallLen(str.data[0]));
        try std.testing.expectEqual(sso16.isLargeLen(city.len), sso16.isLargeLen(str.data[0]));
        try std.testing.expectEqualStrings(city, str.get());
    }

    try std.testing.expect(sCount > 0);
    try std.testing.expect(lCount > 0);
}
test "sso16.clone" {
    const allocator = std.testing.allocator;
    const cities = @embedFile("cities.txt");
    var iter = std.mem.splitScalar(u8, cities, '\n');

    var str: sso16 = .{};
    while (iter.next()) |city| {
        str = try sso16.clone(allocator, city);
        defer str.free(allocator);
        try std.testing.expectEqual(sso16.isSmallLen(city.len), sso16.isSmallLen(str.data[0]));
        try std.testing.expectEqual(sso16.isLargeLen(city.len), sso16.isLargeLen(str.data[0]));
        try std.testing.expectEqualStrings(city, str.get());
    }
}

test "magicnumber.asm" {
    const Context = struct {
        noinline fn magicnumber(alen: u8, blen: u8) u8 {
            const aLarge: bool = sso16.isLargeLen(alen);
            const bLarge: bool = sso16.isLargeLen(blen);
            if (aLarge and bLarge) return 2;
            if (!aLarge and bLarge) return 1;
            if (aLarge and !bLarge) return 1;
            if (!aLarge and !bLarge) return 0;
            unreachable;
        }
        noinline fn magicnumber_branchless(alen: u8, blen: u8) u8 {
            return @as(u8, @intFromBool(sso16.isLargeLen(alen))) + @as(u8, @intFromBool(sso16.isLargeLen(blen)));
        }
        noinline fn magicnumber_asm(alen: u8, blen: u8) u8 {
            return asm volatile ( // NO FOLD
                \\ cmp $15, %al
                \\ setg %al
                \\ and $1, %al
                \\ cmp $15, %bl
                \\ setg %bl
                \\ and $1, %bl
                \\ add %bl, %al
                : [ret] "={al}" (-> u8),
                : [a] "{al}" (alen),
                  [b] "{bl}" (blen),
            );
        }

        fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
            var list = std.ArrayList([]const T){};
            defer list.deinit(allocator);
            var iter = std.mem.splitScalar(T, buffer, delimiter);
            while (iter.next()) |item| try list.append(allocator, item);
            return try list.toOwnedSlice(allocator);
        }
    };

    const cities = try Context.splitScalarToArray(u8, @embedFile("cities.txt"), '\n', std.testing.allocator);
    defer std.testing.allocator.free(cities);

    var str_a: sso16 = .{};
    var str_b: sso16 = .{};
    for (0..cities.len) |i| {
        str_a.set(cities[i]);
        for (i..cities.len) |j| {
            str_b.set(cities[j]);
            const magicnumber_a = Context.magicnumber(str_a.data[0], str_b.data[0]);
            const magicnumber_b = Context.magicnumber_branchless(str_a.data[0], str_b.data[0]);
            const magicnumber_c = Context.magicnumber_asm(str_a.data[0], str_b.data[0]);

            try std.testing.expectEqual(magicnumber_a, magicnumber_b);
            try std.testing.expectEqual(magicnumber_a, magicnumber_c);
        }
    }
}
