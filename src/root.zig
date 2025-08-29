const std = @import("std");

pub const fileMapping = @import("fileMapping.zig");
test fileMapping {
    _ = fileMapping;
}

const blockReaderNs = @import("BlockReader.zig");
pub const BlockReader = blockReaderNs.BlockReader;
test blockReaderNs {
    _ = blockReaderNs;
}

const Stat = @import("Stat.zig");
test Stat {
    _ = Stat;
}

const BRCMapNs = @import("BRCMap.zig");
pub const BRCMap = BRCMapNs.BRCMap;
test BRCMapNs {
    _ = BRCMapNs;
}

pub const sso = @import("sso.zig");
test sso {
    _ = sso;
}

pub fn brcIntParse(str: []const u8) i32 {
    const isNegative: bool = str[0] == '-';
    const isNegativeInt: i32 = @intFromBool(isNegative);
    const isPositiveInt: i32 = @intFromBool(!isNegative);
    const arr: []const u8 = str[@intFromBool(isNegative)..];
    return ((-1 * isNegativeInt) + isPositiveInt) * // sign
        (@as(i32, @intCast(arr[arr.len - 1] - '0')) + // 1s place
            @as(i32, @intCast(arr[arr.len - 3] - '0')) * 10 + // 10s place
            if (arr.len == 4) @as(i32, @intCast(arr[arr.len - 4] - '0')) * 100 else 0); // 100s place
}
test brcIntParse {
    const min: comptime_int = -999;
    const max: comptime_int = 999;

    var buf: [64]u8 = undefined;
    var i: i32 = min;
    @memset(buf[0..], 0);
    while (i <= max) : (i += 1) {
        const f: f128 = @as(f128, @floatFromInt(i)) / 10.0;
        const s = try std.fmt.bufPrint(buf[0..], "{d:.1}", .{f});
        const p = brcIntParse(s);
        std.testing.expectEqual(i, p) catch |e| {
            std.log.err("Parsed \"{s}\" wrong. Expected {d} but found {d}", .{ s, i, p });
            return e;
        };
    }
}

// export fn memeql_ex(aptr: [*]const u8, alen: usize, bptr: [*]const u8, blen: usize) bool {
//     if (alen != blen) return false;
//     const vlen: comptime_int = 32;
//     const L: usize = alen;
//     var l: usize = 0;
//     while ((L - l) >= vlen) {
//         const vaptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&aptr[l]);
//         const vbptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&bptr[l]);
//         const veql: @Vector(vlen, bool) = vaptr.* == vbptr.*;
//         const eql: bool = @reduce(.And, veql);
//         if (!eql) return false;
//         l += vlen;
//     }
//     while (l < L) : (l += 1) if (aptr[l] != bptr[l]) return false;
//     return true;
// }

inline fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
    var list = std.ArrayList([]const T).init(allocator);
    defer list.deinit();
    var iter = std.mem.splitScalar(T, buffer, delimiter);
    while (iter.next()) |item| try list.append(item);
    return try list.toOwnedSlice();
}

pub inline fn memeql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    const vlen: comptime_int = std.simd.suggestVectorLength(u8) orelse 8;
    const L: usize = a.len;
    var l: usize = 0;
    while ((L - l) >= vlen) {
        const va_ptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&a[l]);
        const vb_ptr: *align(1) const @Vector(vlen, u8) = @ptrCast(&b[l]);
        const veql: @Vector(vlen, bool) = va_ptr.* == vb_ptr.*;
        const eql: bool = @reduce(.And, veql);
        if (!eql) return false;
        l += vlen;
    }
    while (l < L) : (l += 1) if (a[l] != b[l]) return false;
    return true;
}

test memeql {
    const cities = @embedFile("cities.txt");
    const cityNames: [][]const u8 = try splitScalarToArray(u8, cities, '\n', std.testing.allocator);
    defer std.testing.allocator.free(cityNames);

    for (0..cityNames.len) |i| {
        const a: []const u8 = cityNames[i];
        for (0..cityNames.len) |j| {
            const b: []const u8 = cityNames[j];
            const expect: bool = std.mem.eql(u8, a, b);
            const found: bool = memeql(a, b);
            std.testing.expectEqual(expect, found) catch |err| {
                std.log.err("memeql failed at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
                return err;
            };
        }
    }
}
