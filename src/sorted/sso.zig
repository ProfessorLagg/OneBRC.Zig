const builtin = @import("builtin");
const std = @import("std");
const compare = @import("compare.zig");
const CompareResult = compare.CompareResult;
const log = std.log.scoped(.SSO);

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
    var cmp: CompareResult = compare.compareNumber(a.len, b.len);
    if (cmp != .Equal) {
        return cmp;
    }

    inline for (0..SmallString.bufsize) |i| {
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
