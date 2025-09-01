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

pub const LineSplitter = @import("LineSplitter.zig");
test LineSplitter {
    const delimiter = '\n';
    const cities = @embedFile("cities.txt");
    var std_iter = std.mem.splitScalar(u8, cities, delimiter);
    var new_iter = LineSplitter{ .buffer = cities };
    var both_null: bool = false;
    while (!both_null) {
        const std_item = std_iter.next();
        const new_item = new_iter.next();
        try std.testing.expectEqual(std_item, new_item);
        both_null = (std_item == null) and (new_item == null);
    }
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

pub inline fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
    var list = std.ArrayList([]const T).init(allocator);
    defer list.deinit();
    var iter = std.mem.splitScalar(T, buffer, delimiter);
    while (iter.next()) |item| try list.append(item);
    return try list.toOwnedSlice();
}

const _asm = @import("_asm.zig");
test "_asm.memeql" {
    const allocator: std.mem.Allocator = std.testing.allocator;

    const cities = @embedFile("cities.txt");
    const cityNames: [][]const u8 = try splitScalarToArray(u8, cities, '\n', allocator);
    defer allocator.free(cityNames);

    for (0..cityNames.len) |i| {
        const a: []const u8 = cityNames[i];
        for (i..cityNames.len) |j| {
            const b: []const u8 = cityNames[j];
            const expect: bool = std.mem.eql(u8, a, b);
            const found: bool = _asm.memeql(a, b);
            std.testing.expectEqual(expect, found) catch |err| {
                std.log.err("memeql failed at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
                return err;
            };
        }
    }
}

pub fn eqlBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len <= 16) {
        if (a.len < 4) {
            const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
            return x == 0;
        }
        var x: u32 = 0;
        for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
        }
        return x == 0;
    }

    // Figure out the fastest way to scan through the input in chunks.
    // Uses vectors when supported and falls back to usize/words when not.
    const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size|
        struct {
            pub const size = vec_size;
            pub const Chunk = @Vector(size, u8);
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return @reduce(.Or, chunk_a != chunk_b);
            }
        }
    else
        struct {
            pub const size = @sizeOf(usize);
            pub const Chunk = usize;
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return chunk_a != chunk_b;
            }
        };

    inline for (1..6) |s| {
        const n = 16 << s;
        if (n <= Scan.size and a.len <= n) {
            const V = @Vector(n / 2, u8);
            var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
            x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
            const zero: V = @splat(0);
            return !@reduce(.Or, x != zero);
        }
    }
    // Compare inputs in chunks at a time (excluding the last chunk).
    for (0..(a.len - 1) / Scan.size) |i| {
        const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
        const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
        if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    // Compare the last chunk using an overlapping read (similar to the previous size strategies).
    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
}
test eqlBytes {
    const cities = @embedFile("cities.txt");
    const cityNames: [][]const u8 = try splitScalarToArray(u8, cities, '\n', std.testing.allocator);
    defer std.testing.allocator.free(cityNames);

    for (0..cityNames.len) |i| {
        const a: []const u8 = cityNames[i];
        for (i..cityNames.len) |j| {
            const b: []const u8 = cityNames[j];
            const expect: bool = std.mem.eql(u8, a, b);
            const found: bool = eqlBytes(a, b);
            std.testing.expectEqual(expect, found) catch |err| {
                std.log.err("eqlBytes failed at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
                return err;
            };
            // std.log.debug("eqlBytes succeeded at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
        }
    }
}
