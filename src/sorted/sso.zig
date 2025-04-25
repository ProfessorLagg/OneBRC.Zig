const builtin = @import("builtin");
const std = @import("std");
const compare = @import("compare.zig");
const CompareResult = compare.CompareResult;
const log = std.log.scoped(.SSO);
const utils = @import("../utils.zig");

pub const SmallString = struct {
    const largeSize: usize = @sizeOf(usize) + @sizeOf(*u8);
    const Tlen_bitcount: u16 = @intCast(std.math.log2_int_ceil(usize, largeSize));
    const Tlen: type = std.meta.Int(.unsigned, Tlen_bitcount);
    pub const bufsize: usize = largeSize - @sizeOf(Tlen);

    buf: [bufsize]u8 align(8) = undefined,
    len: Tlen = 0,
};
pub const LargeString = []u8;
pub const SSO_TYPE = enum(u1) {
    small,
    large,
};
pub const SSO = union(SSO_TYPE) {
    small: SmallString,
    large: LargeString,

    pub inline fn isSmallLen(len: usize) bool {
        return len <= SmallString.bufsize;
    }

    pub inline fn init(allocator: *std.mem.Allocator, str: []const u8) !SSO {
        var result: SSO = undefined;
        if (SSO.isSmallLen(str.len)) {
            std.debug.assert(str[0..].len <= SmallString.bufsize);
            result = SSO{ .small = SmallString{} };
            result.small.len = @truncate(str.len);
            std.mem.copyForwards(u8, result.small.buf[0..str.len], str[0..]);
            return result;
        } else {
            std.debug.assert(str[0..].len > SmallString.bufsize);
            result = SSO{ .large = try allocator.alloc(u8, str.len) };
            std.mem.copyForwards(u8, result.large[0..], str[0..]);
            return result;
        }
    }

    pub inline fn clone(self: *const SSO, allocator: *std.mem.Allocator) !SSO {
        const deref = self.*;
        return switch (deref) {
            .small => deref,
            .large => try SSO.init(allocator, self.large),
        };
    }

    pub inline fn deinit(self: SSO, allocator: *std.mem.Allocator) void {
        const tag: SSO_TYPE = @as(SSO_TYPE, self);
        log.debug("deinit SSO.{s}", .{@tagName(tag)});
        switch (tag) {
            .small => {},
            .large => {
                allocator.free(self.large);
            },
        }
    }

    pub inline fn create(str: []const u8) SSO {
        var result: SSO = undefined;
        if (SSO.isSmallLen(str.len)) {
            std.debug.assert(str[0..].len <= SmallString.bufsize);
            result = SSO{ .small = SmallString{} };
            result.small.len = @truncate(str.len);
            std.mem.copyForwards(u8, result.small.buf[0..str.len], str[0..]);
            return result;
        } else {
            std.debug.assert(str[0..].len > SmallString.bufsize);
            result = SSO{ .large = @constCast(str) };
            return result;
        }
    }

    pub inline fn toString(self: *const SSO) []const u8 {
        const tag = @as(SSO_TYPE, self.*);
        return switch (tag) {
            .small => self.small.buf[0..self.small.len],
            .large => self.large,
        };
    }
};
inline fn compareSmall(a: *const SmallString, b: *const SmallString) CompareResult {
    std.debug.assert(SmallString.bufsize > @sizeOf(usize));
    const veclen = @sizeOf(usize);

    const vec_a: *const usize = @ptrCast(&a.buf[0]);
    const vec_b: *const usize = @ptrCast(&b.buf[0]);

    var cmp: CompareResult = compare.compareNumber(vec_a.*, vec_b.*);
    if (cmp != .Equal) {
        return cmp;
    }

    inline for (veclen..SmallString.bufsize) |i| {
        cmp = compare.compareNumber(a.buf[i], b.buf[i]);
        if (cmp != .Equal) {
            return cmp;
        }
    }
    return .Equal;
}
pub inline fn compareSSO(a: *const SSO, b: *const SSO) CompareResult {
    const aTag: SSO_TYPE = @as(SSO_TYPE, a.*);
    const bTag: SSO_TYPE = @as(SSO_TYPE, b.*);

    if (aTag == .small and bTag == .small) {
        return compareSmall(&a.small, &b.small);
    }

    const aSlice: []const u8 = switch (aTag) {
        .small => a.small.buf[0..a.small.len],
        .large => a.large[0..],
    };
    const bSlice: []const u8 = switch (bTag) {
        .small => b.small.buf[0..b.small.len],
        .large => b.large[0..],
    };
    return compare.compareString(aSlice, bSlice);
}

pub const BRCString = struct {
    const ArrSize = @sizeOf(usize);
    const TArr = [ArrSize]u8;

    const u8f = packed struct {
        const TSelf = @This();
        len: u7 = 0,
        flag: u1 = 0,

        pub inline fn isSmall(self: TSelf) bool {
            return self.len <= ArrSize;
        }
        pub inline fn isLarge(self: TSelf) bool {
            return self.len > ArrSize;
        }
    };

    /// meta.flag == 1 when data is an owned slice on the heap
    meta: u8f = .{},
    data: usize = 0,

    inline fn asSliceS(self: *const BRCString) []const u8 {
        const a: TArr = @bitCast(self.data);
        return a[0..self.meta.len];
    }
    pub fn asSlice(self: *const BRCString) []const u8 {
        if (self.meta.isSmall()) return self.asSliceS();
        var r: []const u8 = undefined;
        r.ptr = @ptrFromInt(self.data);
        r.len = self.meta.len;
        return r;
    }

    inline fn initS(string: []const u8) BRCString {
        std.debug.assert(string.len <= ArrSize);
        var arr: TArr = undefined;
        @memset(arr[0..], 0);
        utils.mem.copyForwards(u8, arr[0..], string);

        var r = BRCString{};
        // r.meta.flag = 0;
        r.meta.len = @truncate(string.len);
        r.data = @bitCast(arr);
        log.debug("initS:  {any} from \"{s}\"", .{ r, string });
        return r;
    }
    inline fn initL(allocator: std.mem.Allocator, string: []const u8) !BRCString {
        const str_clone: []u8 = try allocator.alloc(u8, string.len);
        utils.mem.copy(u8, str_clone, string);

        var r = BRCString{};
        r.meta.flag = 1;
        r.meta.len = @truncate(str_clone.len);
        r.data = @intFromPtr(string.ptr);
        log.debug("initL:  {any} from \"{s}\"", .{ r, string });
        return r;
    }
    pub fn init(allocator: std.mem.Allocator, string: []const u8) !BRCString {
        std.debug.assert(string.len <= comptime std.math.maxInt(u7));
        if (string.len <= ArrSize) return initS(string);
        return initL(allocator, string);
    }
    pub fn create(string: []const u8) BRCString {
        if (string.len <= ArrSize) return initS(string);
        var r = BRCString{};
        // r.meta.flag = 0;
        r.meta.len = @truncate(string.len);
        r.data = @intFromPtr(string.ptr);
        log.debug("create: {any} from \"{s}\"", .{ r, string });
        return r;
    }
    pub inline fn clone(self: *const BRCString, allocator: std.mem.Allocator) !BRCString {
        if (self.meta.isSmall()) return self.*;

        return try initL(allocator, self.asSlice());
    }
    pub fn deinit(self: *BRCString, allocator: std.mem.Allocator) void {
        if (self.meta.flag == 1 and self.meta.isLarge()) {
            const s = self.asSlice();
            log.debug("deinit: len: {d}, flag: {d}, data: {d} | 0x{X}, slice: \"{s}\"", .{ self.meta.len, self.meta.flag, self.data, self.data, s });
            allocator.free(s);
            // _ = &allocator;
        }
    }

    inline fn cmpS(a: *const BRCString, b: *const BRCString) CompareResult {
        const avec: @Vector(@sizeOf(TArr), u8) = @bitCast(a.data);
        const bvec: @Vector(@sizeOf(TArr), u8) = @bitCast(b.data);

        const invert_vector: @Vector(@sizeOf(TArr), i8) = comptime @splat(-1);
        const ltv: @Vector(@sizeOf(TArr), i8) = @as(@Vector(@sizeOf(TArr), i8), @intCast(@intFromBool(avec < bvec))) * invert_vector;
        const gtv: @Vector(@sizeOf(TArr), i8) = @intCast(@intFromBool(avec > bvec));

        const sumv: @Vector(@sizeOf(TArr), i8) = ltv + gtv;
        inline for (0..@sizeOf(TArr)) |i| {
            if (sumv[i] != 0) return @enumFromInt(sumv[i]);
        }
        return .Equal;
    }

    inline fn cmpL(a: *const BRCString, b: *const BRCString) CompareResult {
        const as: []const u8 = a.asSlice();
        const bs: []const u8 = b.asSlice();
        return compare.compareStringR(&as, &bs);
    }
    pub fn cmp(a: BRCString, b: BRCString) CompareResult {
        const maxlen: u7 = @max(a.meta.len, b.meta.len);
        if (maxlen > ArrSize) return cmpL(&a, &b);
        return cmpS(&a, &b);
    }
    pub fn cmpR(a: *const BRCString, b: *const BRCString) CompareResult {
        const maxlen: u7 = @max(a.meta.len, b.meta.len);
        if (maxlen > ArrSize) return cmpL(a, b);
        return cmpS(a, b);
    }
};
