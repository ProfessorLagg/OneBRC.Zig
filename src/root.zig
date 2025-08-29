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

pub const Stat = @import("Stat.zig");
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

pub const sorting = @import("sorting.zig");
test sorting {
    _ = sorting;
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

inline fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
    var list = std.ArrayList([]const T).init(allocator);
    defer list.deinit();
    var iter = std.mem.splitScalar(T, buffer, delimiter);
    while (iter.next()) |item| try list.append(item);
    return try list.toOwnedSlice();
}

export fn eqlmask32(a: *align(1) const anyopaque, b: *align(1) const anyopaque) u32 {
    return asm volatile ( // NOFOLD
        \\ vmovups (%rsi), %ymm1
        \\ vmovups (%rdi), %ymm2
        \\ vpcmpeqb %ymm2, %ymm1, %ymm0
        \\ vpmovmskb %ymm0, %eax
        : [ret] "={eax}" (-> u32),
        : [a] "rsi" (a),
          [b] "rdi" (b),
    );
}

export fn eqlmask16(a: *align(1) const anyopaque, b: *align(1) const anyopaque) u16 {
    return asm volatile ( // NOFOLD
        \\ xor %eax, %eax
        \\ vmovups (%rsi), %xmm1
        \\ vmovups (%rdi), %xmm2
        \\ vpcmpeqb %xmm2, %xmm1, %xmm0
        \\ vpmovmskb %xmm0, %eax
        : [ret] "={al}" (-> u16),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
        : "eax"
    );
}

/// compares 32 bytes using SIMD. Returns true if all bytes match, otherwise false
export fn eql32(a: *align(1) const anyopaque, b: *align(1) const anyopaque) bool {
    return asm volatile ( // NOFOLD
        \\ vmovups (%rsi), %ymm1
        \\ vmovups (%rdi), %ymm2
        \\ vpcmpeqb %ymm2, %ymm1, %ymm0
        \\ vpmovmskb %ymm0, %eax
        \\ cmp $-1, %eax
        \\ sete %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
        : "eax"
    );
}

/// compares 16 bytes using SIMD. Returns true if all bytes match, otherwise false
export fn eql16(a: *align(1) const anyopaque, b: *align(1) const anyopaque) bool {
    return asm volatile ( // NOFOLD
        \\ vmovups (%rsi), %xmm1
        \\ vmovups (%rdi), %xmm2
        \\ vpcmpeqb %xmm2, %xmm1, %xmm0
        \\ vpmovmskb %xmm0, %eax
        \\ cmp $-1, %ax
        \\ sete %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
        : "eax"
    );
}

pub inline fn memeql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    const L: usize = a.len;
    var i: usize = 0;
    while ((L - i) >= 32) {
        const eql: bool = eql32(&a[i], &b[i]);
        if (!eql) return false;
        i += 32;
    }
    while ((L - i) >= 16) {
        const eql: bool = eql16(&a[i], &b[i]);
        if (!eql) return false;
        i += 16;
    }
    while (i < L) : (i += 1) if (a[i] != b[i]) return false;
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
