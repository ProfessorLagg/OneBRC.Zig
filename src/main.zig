const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

const lib = @import("brc_lib");

// pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
//     std.log.err("{s}{any}", .{ msg, trace });
//     std.process.exit(1);
// }

// following files have at most 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000.txt";

// following files have 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_trail.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const static_allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

var gpa: std.mem.Allocator = undefined;
var io: Io = undefined;

pub fn main(init: std.process.Init.Minimal) !void {
    gpa = static_allocator;

    var threaded: std.Io.Threaded = .init(gpa, std.Io.Threaded.InitOptions{
        .argv0 = .init(init.args),
        .environ = init.environ,
        .async_limit = .limited(try std.Thread.getCpuCount() - 1),
        .concurrent_limit = .unlimited,
    });
    io = threaded.io();

    // const args = try std.process.argsAlloc(gpa);
    // defer std.process.argsFree(gpa, args);
    const pargs: lib.Args2 = try .init(init.args, gpa);
    const filepath = if (pargs.args.len > 0) pargs.args[0] else debugfilepath;

    //try clearFileCache();
    // try Parser.DefaultParser.parseFile(static_allocator, filepath);
    //try dbg();
    //try benchmark_parseLine();
    // try benchmark_findKeyIndex();
    //try baseline.read(filepath);
    //try bench(filepath);
    try runSingleThread(filepath);
}

fn runSingleThread(filePath: []const u8) !void {
    std.debug.print("Attempting to open file '{s}'\n", .{ filePath });

    const file = try lib.fs.openFile(filePath);
    defer lib.fs.closeFile(file);

    var buffer: [4096]u8 = undefined;
    const readLen = try lib.fs.readFile(file, buffer[0..]);

    std.debug.print("Read {d} bytes from '{s}'\n", .{ readLen, filePath });
}

fn clearFileCache() !void {
    const stderr = lib.getStderr();
    defer stderr.flush() catch unreachable;
    switch (builtin.target.os.tag) {
        .windows => {
            var memstat: lib.c.MEMORYSTATUSEX = std.mem.zeroes(lib.c.MEMORYSTATUSEX);
            memstat.dwLength = @sizeOf(lib.c.MEMORYSTATUSEX);
            if (lib.c.GlobalMemoryStatusEx(&memstat) == 0) {
                const err = std.os.windows.GetLastError();
                return std.os.windows.unexpectedError(err);
            }

            const avail: usize = @intCast(memstat.ullAvailPhys);
            try stderr.print("Found {Bi} available physical memory\n", .{avail});
            try stderr.flush();
            const alloc = try gpa.alloc(u8, avail);
            @memset(alloc[0..], '@');
            gpa.free(alloc);
        },

        else => @compileError("Not yet implemented"),
    }
}
