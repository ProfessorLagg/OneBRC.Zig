test "TempTest" {
    const std = @import("std");
    var b: i8 = std.math.minInt(i8);
    while (true) {
        const d = ~b;
        const bp: u8 = @bitCast(b);
        const dp: u8 = @bitCast(d);
        std.log.info("~({d:>4}) | {b:0>8} == {d:>4} | {b:0>8}", .{ b, bp, d, ~dp });

        if (b == std.math.maxInt(@TypeOf(b))) break;
        b += 1;
    }
}

pub const _asm = @import("_asm.zig");
test _asm {
    _ = _asm;
}

pub const BRCParser = @import("BRCParser.zig");
test BRCParser {
    _ = BRCParser;
}

pub const DynamicBuffer = @import("DynamicBuffer.zig");
test DynamicBuffer {
    _ = DynamicBuffer;
}

pub const sso = @import("sso.zig");
test sso {
    _ = sso;
}
