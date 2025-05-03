const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const parsing = @import("parsing.zig");
const parallel = @import("parallel/parallel.zig");
const sorted = @import("sorted/sorted.zig");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseSmall => .debug,
        .ReleaseFast => .debug,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .SortedArrayMap, .level = .warn },
        .{ .scope = .DelimReader, .level = .err },
        .{ .scope = .Lines, .level = .err },
        .{ .scope = .SSO, .level = .err },
    },
};

var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

pub fn main() !void {
    //try test_packed_structs();
    //try parseArgs();

    // try printArgs();

    // try run();
    try debug();
    // try debug_read();
}

fn parseArgs() !void {
    const allocator = std.heap.c_allocator;

    // Parse args into string array (error union needs 'try')
    const args_base = std.process.argsAlloc(allocator) catch {
        @panic("Could not allocate args");
    };
    defer std.process.argsFree(allocator, args_base);

    const args = args_base[1..];
    if (args.len <= 0 or args[0].len < 1) return;
    debugfilepath = args[0];
}

fn printArgs() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Get and print them!
    std.debug.print("There are {d} args:\n", .{args.len});
    for (args) |arg| {
        std.debug.print("  {s}\n", .{arg});
    }
}

fn run() !void {
    _ = try parsing.parse(debugfilepath[0..], true);
}
fn debug() !void {
    const stdout = std.io.getStdOut().writer();

    const parseFn = comptime switch (builtin.single_threaded) {
        true => parsing.parse,
        false => parsing.parseParallel,
    };

    const thread_mode_str = comptime switch (builtin.single_threaded) {
        true => "single-threaded",
        false => "multi-threaded",
    };

    try std.fmt.format(stdout, "Running {s}-benchmark on file: {s}\n", .{ thread_mode_str, debugfilepath });
    const start_time = std.time.nanoTimestamp();
    const parseResult: parsing.ParseResult = @call(.never_inline, parseFn, .{ debugfilepath[0..], false }) catch |err| {
        std.debug.panic("{any}{any}", .{ err, @errorReturnTrace() });
    };

    const end_time = std.time.nanoTimestamp();

    const ns: u64 = @intCast(end_time - start_time);
    const nsf: f64 = @floatFromInt(ns);
    const s: f64 = nsf / std.time.ns_per_s;
    const ns_per_line: f64 = nsf / @as(f64, @floatFromInt(parseResult.lineCount));

    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys;
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    const stat: std.fs.File.Stat = blk: {
        var buf: [4096]u8 = undefined;
        const abspath = try std.fs.cwd().realpath(debugfilepath, buf[0..]);
        var file = try std.fs.openFileAbsolute(abspath, comptime std.fs.File.OpenFlags{ //NOFOLD
            .mode = .read_only,
            .lock = .none,
            .lock_nonblocking = false,
            .allow_ctty = false,
        });
        defer file.close();
        const stat = try file.stat();
        break :blk stat;
    };

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(stat.size)) / s);
    try std.fmt.format(stdout, "parsed {d:.0} lines in {any} | {d:.2} ns/line | found {d} unique keys ({d:.2}%) | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, uniqueKeys, key_percent, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

fn debug_read() !void {
    const stdout = std.io.getStdOut().writer();

    const thread_mode_str = comptime switch (builtin.single_threaded) {
        true => "single-threaded",
        false => "multi-threaded",
    };

    try std.fmt.format(stdout, "Running (READ ONLY) {s}-benchmark on file: {s}\n", .{ thread_mode_str, debugfilepath });
    const start_time = std.time.nanoTimestamp();
    const parseResult: parsing.ParseResult = parsing.read(debugfilepath[0..]) catch |err| {
        std.debug.panic("{any}{any}", .{ err, @errorReturnTrace() });
    };

    const end_time = std.time.nanoTimestamp();

    const ns: u64 = @intCast(end_time - start_time);
    const nsf: f64 = @floatFromInt(ns);
    const s: f64 = nsf / std.time.ns_per_s;
    const ns_per_line: f64 = nsf / @as(f64, @floatFromInt(parseResult.lineCount));

    const stat: std.fs.File.Stat = blk: {
        var buf: [4096]u8 = undefined;
        const abspath = try std.fs.cwd().realpath(debugfilepath, buf[0..]);
        var file = try std.fs.openFileAbsolute(abspath, comptime std.fs.File.OpenFlags{ //NOFOLD
            .mode = .read_only,
            .lock = .none,
            .lock_nonblocking = false,
            .allow_ctty = false,
        });
        defer file.close();
        const stat = try file.stat();
        break :blk stat;
    };

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(stat.size)) / s);
    try std.fmt.format(stdout, "read {d:.0} lines in {any} | {d:.2} ns/line | read speed: {d:.2}/s\n", .{ parseResult.lineCount, std.fmt.fmtDuration(ns), ns_per_line, std.fmt.fmtIntSizeBin(bytes_per_second) });
}

const ContainsIterator = struct {
    strings: []const []const u8,
    needle: []const u8,
    index: usize = 0,
    fn next(self: *ContainsIterator) ?[]const u8 {
        const index = self.index;
        for (self.strings[index..]) |string| {
            self.index += 1;
            if (std.mem.indexOf(u8, string, self.needle)) |_| {
                return string;
            }
        }
        return null;
    }
};

test "custom iterator" {
    var iter = ContainsIterator{
        .strings = &[_][]const u8{ "one", "two", "three" },
        .needle = "e",
    };

    try std.testing.expectEqual("one", iter.next().?);
    try std.testing.expectEqual("three", iter.next().?);
    try std.testing.expectEqual(null, iter.next());
}

fn test_packed_structs() !void {
    const PS = packed struct {
        data: u7 = 0,
        flag: u1 = 1,
    };

    var v = PS{ .data = 123, .flag = 0 };

    const stdout = std.io.getStdOut().writer();
    try std.fmt.format(stdout, "unset = {any}\n", .{v});
    v.flag = 1;
    try std.fmt.format(stdout, "set   = {any}\n", .{v});
    v.data = 45;
    try std.fmt.format(stdout, "set   = {any}\n", .{v});
    v.flag = 0;
    try std.fmt.format(stdout, "unset = {any}\n", .{v});

    try std.fmt.format(stdout, "size: {d}, align: {d}\n", .{ @sizeOf(PS), @alignOf(PS) });

    try std.fmt.format(stdout, "name: {s}, size: {d}, align: {d}\n", .{ @typeName([*]const u8), @sizeOf([*]const u8), @alignOf([*]const u8) });
}
