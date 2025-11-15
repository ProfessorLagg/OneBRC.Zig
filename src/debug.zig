const builtin = @import("builtin");
const std = @import("std");

const debugEnabled = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

pub inline fn assert(ok: bool) void {
    comptime if (debugEnabled) return;
    if (!ok) unreachable;
}

pub inline fn assertMsg(ok: bool, msg: []const u8) void {
    comptime if (debugEnabled) return;
    if (!ok) @panic(msg);
}
