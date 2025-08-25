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

const BRCMap = @import("BRCMap.zig");
test BRCMap {
    _ = BRCMap;
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
