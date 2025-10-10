const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;
const lib = @import("brc_lib");

fn read_stdio(buffer: []u8, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var readsize = try file.read(buffer[0..]);
    while (readsize > 0) : (readsize = try file.read(buffer[0..])) {}
}

fn read_ATTRIBUTE_NORMAL(buffer: []u8, path: []const u8) !void {
    // const path_w = try windows.sliceToPrefixedFileW(std.fs.cwd().fd, path);
    const hFile: lib.c.HANDLE = lib.c.CreateFileA( // nofold
        @ptrCast(path.ptr) // [in] lpFileName
        , lib.c.GENERIC_READ // [in] dwDesiredAccess
        , lib.c.FILE_SHARE_READ // [in] dwShareMode
        , null // [in, optional] lpSecurityAttributes
        , lib.c.OPEN_EXISTING // [in] dwCreationDisposition
        , lib.c.FILE_ATTRIBUTE_NORMAL // [in] dwFlagsAndAttributes
        , null // [in, optional] hTemplateFile
    );
    std.debug.assert(hFile != null);
    var readsize: lib.c.DWORD = std.math.maxInt(lib.c.DWORD);
    while (readsize > 0) {
        if (lib.c.ReadFile(hFile // [in] hFile
            , buffer.ptr // [out] lpBuffer
            , @intCast(buffer.len) // [in] nNumberOfBytesToRead
            , &readsize // [out, optional] lpNumberOfBytesRead
            , null // [in, out, optional] lpOverlapped
        ) == 0) return windows.unexpectedError(windows.GetLastError());
    }
}

fn read_NO_BUFFERING_SEQUENTIAL_SCAN(buffer: []u8, path: []const u8) !void {
    // const path_w = try windows.sliceToPrefixedFileW(std.fs.cwd().fd, path);
    const hFile: lib.c.HANDLE = lib.c.CreateFileA( // nofold
        @ptrCast(path.ptr) // [in] lpFileName
        , lib.c.GENERIC_READ // [in] dwDesiredAccess
        , lib.c.FILE_SHARE_READ // [in] dwShareMode
        , null // [in, optional] lpSecurityAttributes
        , lib.c.OPEN_EXISTING // [in] dwCreationDisposition
        , lib.c.FILE_ATTRIBUTE_NORMAL | lib.c.FILE_FLAG_NO_BUFFERING | lib.c.FILE_FLAG_SEQUENTIAL_SCAN // [in] dwFlagsAndAttributes
        , null // [in, optional] hTemplateFile
    );
    std.debug.assert(hFile != null);
    var readsize: lib.c.DWORD = std.math.maxInt(lib.c.DWORD);
    while (readsize > 0) {
        if (lib.c.ReadFile(hFile // [in] hFile
            , buffer.ptr // [out] lpBuffer
            , @intCast(buffer.len) // [in] nNumberOfBytesToRead
            , &readsize // [out, optional] lpNumberOfBytesRead
            , null // [in, out, optional] lpOverlapped
        ) == 0) return windows.unexpectedError(windows.GetLastError());
    }
}

pub fn read(path: []const u8) !void {
    const FileReadFn = struct {
        name: []const u8,
        function: fn ([]u8, []const u8) anyerror!void,
    };
    const functions = comptime [_]FileReadFn{
        FileReadFn{ .name = "read_NO_BUFFERING_SEQUENTIAL_SCAN", .function = read_NO_BUFFERING_SEQUENTIAL_SCAN },
        FileReadFn{ .name = "read_ATTRIBUTE_NORMAL", .function = read_ATTRIBUTE_NORMAL },
        FileReadFn{ .name = "read_stdio", .function = read_stdio },
    };
    const bufferSizes = comptime [_]usize{
        //4096,
        //8192,
        //16384,
        //32768,
        65536,
        131072,
        262144,
        524288,
        1048576,
        2097152,
        4194304,
        8388608,
        16777216,
        33554432,
        67108864,
        134217728,
        268435456,
        536870912,
        1073741824,
    };

    var file_size: u64 = 0;
    {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        file_size = file.getEndPos() catch (try file.stat()).size;
    }

    var maxbufsize: usize = file_size;
    for (bufferSizes) |bs| maxbufsize = @max(maxbufsize, bs);
    std.debug.print("using max buffer size = {Bi:.3}\n", .{maxbufsize});

    const bufptr = try windows.VirtualAlloc(null, maxbufsize, windows.MEM_COMMIT | windows.MEM_RESERVE, windows.PAGE_READWRITE);
    defer windows.VirtualFree(bufptr, maxbufsize, windows.MEM_DECOMMIT);
    const fullbuf: []align(4096) u8 = @as([*]align(4096) u8, @ptrCast(@alignCast(bufptr)))[0..maxbufsize];

    var timer = try std.time.Timer.start();
    inline for (functions) |func| {
        for (0..bufferSizes.len) |i| {
            @memset(fullbuf[0..], 0);
            const bufsize = bufferSizes[i];
            const buffer = fullbuf[0..bufsize];

            timer.reset();
            try func.function(buffer, path);
            const tns = timer.read();
            std.debug.print("{s}  {Bi:>6.0}  {D:>10.3}\n", .{ func.name, bufsize, tns });
        }

        timer.reset();
        try func.function(fullbuf, path);
        const tns = timer.read();
        std.debug.print("{s}  {Bi:>6.0}  {D:>10.3}\n", .{ func.name, fullbuf.len, tns });
    }
}
