const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .err,
        .ReleaseSmall => .err,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        // .{ .scope = .DelimReader, .level = .err },
        // .{ .scope = .BRCMap, .level = .err },
        // .{ .scope = .Lines, .level = .err },
        // .{ .scope = .BRCHashMap, .level = .err },
    },
};

// following files have at most 10 000 keys, and likely more than 1 instance of each key
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000.txt";

// following files have 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

pub fn main() !void {
    const filemap = try lib.fileMapping.map(debugfilepath);
    defer lib.fileMapping.unmap(filemap);

    const stdout = std.io.getStdOut();
    _ = try stdout.write(filemap.slice);
}
