const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const ut = lib.utils;
const ParseResult = lib.BRCParser.BRCParseResult;

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .err,
        .ReleaseSmall => .err,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .DelimReader, .level = .err },
        .{ .scope = .BRCMap, .level = .err },
        .{ .scope = .Lines, .level = .err },
        .{ .scope = .BRCHashMap, .level = .err },
    },
};

// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple.rev.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\simple2.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\verysmall.txt";

// following files have more than 1 instance of each key, and 41343 keys in total
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\small.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\medium.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1GB.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\large.txt";

// following files have at most 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000.txt";

// following files have 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

// const allocator = std.heap.c_allocator;

pub fn main() !void {
    defer lib.utils.debug.flush();
    // temp() catch |e| catch_print(e);
    bench_parse() catch |e| catch_print(e);
    // bench_read() catch |e| catch_print(e);
    //run() catch |e| catch_print(e);
}

fn catch_print(e: anyerror) void {
    std.fmt.format(std.io.getStdErr().writer(), "{any}{any}", .{ e, @errorReturnTrace() }) catch @panic("Format failed");
}

fn temp() !void {
    const file: std.fs.File = try std.fs.cwd().openFile(debugfilepath, .{});
    const dst_dir_path: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\temp";
    const dst_dir: std.fs.Dir = try std.fs.cwd().openDir(dst_dir_path, .{});

    const BlockReader: type = lib.BRCBlockReader(@TypeOf(file), 8_388_608);
    var blockReader = BlockReader.init(allocator, file);
    var blockId: usize = 1;
    while (try blockReader.next()) |block| : (blockId += 1) {
        const fileName = try std.fmt.allocPrint(allocator, "block {d}.txt", .{blockId});
        defer allocator.free(fileName);
        var out_file = try dst_dir.createFile(fileName, .{});
        defer out_file.close();
        _ = try out_file.writeAll(block);
    }
}

pub fn bench_parse() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;

    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    const filesize: u64 = parser.file.getEndPos() catch (try parser.file.stat()).size;

    var result: ParseResult = try parser.parse();
    parser.deinit();
    ut.debug.flush();
    const linecount = result.linecount;
    const keycount = result.entries.len;
    result.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = duration_ns / linecount;

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(filesize)) / (@as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_s)));
    const threadTagStr = comptime switch (builtin.single_threaded) {
        true => "Single Thread",
        false => "Multi Thread ",
    };
    try std.fmt.format(stdout, "{s} | Parsed {d} lines | {d} keys | in {d:.3} ({d:.3}/line | {d:.3}/s)\n", .{
        threadTagStr,
        linecount,
        keycount,
        std.fmt.fmtDuration(duration_ns),
        std.fmt.fmtDuration(ns_per_line),
        std.fmt.fmtIntSizeBin(bytes_per_second),
    });
}

pub fn bench_read() !void {
    const stdout = std.io.getStdOut().writer();
    var timer = std.time.Timer.start() catch unreachable;

    var parser = try lib.BRCParser.init(allocator, debugfilepath);
    var result: ParseResult = try parser.read();

    const filesize: u64 = (try parser.file.stat()).size;
    parser.deinit();

    const linecount = result.linecount;
    const keycount = result.entries.len;
    result.deinit();

    const duration_ns: u64 = timer.read();
    const ns_per_line: u64 = duration_ns / linecount;

    const bytes_per_second: u64 = @intFromFloat(@as(f64, @floatFromInt(filesize)) / (@as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_s)));
    const threadTagStr = comptime switch (builtin.single_threaded) {
        true => "Single Thread",
        false => "Multi Thread ",
    };
    try std.fmt.format(stdout, "{s} | Parsed {d} lines | {d} keys | in {d:.3} ({d:.3}/line | {d:.3}/s)\n", .{
        threadTagStr,
        linecount,
        keycount,
        std.fmt.fmtDuration(duration_ns),
        std.fmt.fmtDuration(ns_per_line),
        std.fmt.fmtIntSizeBin(bytes_per_second),
    });
}

pub fn run() !void {
    const BRCParser = lib.BRCParser;
    const BRCParseResult = BRCParser.BRCParseResult;

    var parser: BRCParser = try lib.BRCParser.init(allocator, debugfilepath);
    var parsed: BRCParseResult = try parser.parse();
    defer parsed.deinit();
    parser.deinit();

    const stdout = std.io.getStdOut().writer();
    var bufwri = std.io.bufferedWriter(stdout);
    const writer = bufwri.writer();
    writer.writeByte('{') catch unreachable;
    var i: usize = parsed.entries.len;
    while (i > 1) {
        i -= 1;
        const final = parsed.entries[i].val.finalize();
        std.fmt.format(writer, "{s}={d:.1}/{d:.1}/{d:.1}, ", .{ parsed.entries[i].key, final.min, final.mean, final.max }) catch unreachable;
    }
    i -= 1;
    const final = parsed.entries[i].val.finalize();
    std.fmt.format(writer, "{s}={d:.1}/{d:.1}/{d:.1}", .{ parsed.entries[i].key, final.min, final.mean, final.max }) catch unreachable;
    writer.writeByte('}') catch unreachable;
    bufwri.flush() catch unreachable;
}
