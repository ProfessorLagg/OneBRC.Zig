const builtin = @import("builtin");
const std = @import("std");
const lib = @import("zig_lib");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseSmall => .warn,
        .ReleaseFast => .warn,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .SortedArrayMap, .level = .warn },
        .{ .scope = .DelimReader, .level = .err },
        .{ .scope = .Lines, .level = .err },
        .{ .scope = .SSO, .level = .err },
    },
};

// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

pub fn main() !void {}
