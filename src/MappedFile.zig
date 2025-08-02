const builtin = @import("builtin");
const std = @import("std");
const ut = @import("utils.zig");

const page_size_min = std.heap.page_size_min;

const Options = struct {
    /// If the MappedFile should allow writing
    enableWriting: bool,
    /// If the MappedFile should be created using large pages
    largePages: bool = false,
};

pub fn MappedFile(comptime options: Options) type {
    return switch (builtin.os.tag) {
        .windows => WindowsMappedFile(options),
        else => FakeMappedFile(options),
    };
}

fn FakeMappedFile(comptime options: Options) type {
    return struct {
        const Self = @This();

        pub const View = struct {
            parent: *Self,
            bytes: []u8,

            pub fn destroy(self: *View) void {
                self.parent.destroyView(self);
            }
        };

        file: std.fs.File,
        buffer: []u8,

        pub fn init(path: []const u8) !Self {
            if (options.largePages) @panic("Not implemented yet");

            const fileOpenMode: std.fs.File.OpenMode = if (options.enableWriting) .read_write else .read_only;
            const file: std.fs.File = try std.fs.cwd().openFile(path, .{
                .mode = fileOpenMode,
            });
            const buffer: []u8 = try file.readToEndAlloc(
                ut.mem.staticAllocator,
                std.process.totalSystemMemory() catch std.math.maxInt(usize),
            );
            return Self{
                .file = file,
                .buffer = buffer,
            };
        }
        pub fn deinit(self: *Self) void {
            self.flush() catch |e| std.log.err("flush failed: {any}{any}", .{ e, @errorReturnTrace() });
            ut.mem.staticAllocator.free(self.buffer);
            self.file.close();
        }
        pub fn flush(self: *Self) void {
            if (options.enableWriting) {
                self.file.seekTo(0) catch return; // TODO log error
                self.file.writeAll(self.buffer) catch return; // TODO log error
            }
        }

        /// Returns the size of this mapped file
        pub fn getSize(self: *Self) usize {
            return self.buffer.len;
        }

        /// Creates a view into the MappedFile, starting at `start` and ending at `end`
        /// Size of the resulting view is in the range 0 <= size <= len
        pub fn createView(self: *Self, start: usize, len: usize) !View {
            var bytes: []u8 = self.buffer[start..];
            bytes.len = @min(bytes.len, len);

            std.log.debug("view: [{d}..{d}]", .{
                @intFromPtr(&bytes[0]) - @intFromPtr(&self.buffer[0]),
                @intFromPtr(&bytes[bytes.len - 1]) - @intFromPtr(&self.buffer[0]) + 1,
            });
            return View{
                .parent = self,
                .bytes = bytes[0..],
            };
        }
        pub fn destroyView(self: *Self, view: *View) void {
            std.debug.assert(@intFromPtr(self) == @intFromPtr(view.parent));
            self.flush();
        }
    };
}
fn WindowsMappedFile(comptime options: Options) type {
    comptime if (options.largePages) @panic("Not Supported");

    return struct {
        const c = @cImport({
            @cInclude("memoryapi.h");
            @cInclude("sysinfoapi.h");
        });
        const Self = @This();
        pub const View = struct {
            baseAddress: *anyopaque,
            bytes: []u8,

            pub fn destroy(self: *View) void {
                _ = c.UnmapViewOfFile(self.baseAddress);
            }
        };

        systemInfo: c.SYSTEM_INFO = .{},
        file: std.fs.File,
        handle: c.HANDLE,
        size: usize,

        pub fn init(path: []const u8) !Self {
            const fileOpenMode: std.fs.File.OpenMode = if (options.enableWriting) .read_write else .read_only;
            const file: std.fs.File = try std.fs.cwd().openFile(path, .{
                .mode = fileOpenMode,
            });

            const size: u64 = file.getEndPos() catch (try file.stat()).size;
            if (size > std.math.maxInt(usize)) return std.fs.File.OpenError.FileTooBig;

            const handle: c.HANDLE = c.CreateFileMappingW(
                file.handle, //hFile
                null, //lpFileMappingAttributes
                if (options.enableWriting) c.PAGE_READWRITE else c.PAGE_READONLY, //flProtect
                0, //dwMaximumSizeHigh
                0, //dwMaximumSizeLow
                null, //lpName
            );

            if (handle == null) return error.CreateFileMappingFailed;

            var r: Self = Self{
                .file = file,
                .handle = handle,
                .size = size,
            };
            c.GetSystemInfo(&r.systemInfo);
            return r;
        }

        pub fn deinit(self: *Self) void {
            self.file.close();
        }
        /// Creates a view into the MappedFile, starting at `start` and ending at `end`
        /// Size of the resulting view is in the range 0 <= size <= len
        pub fn createView(self: *Self, start: usize, len: usize) !View {
            const rem: usize = start % @as(usize, @intCast(self.systemInfo.dwAllocationGranularity));
            const fileOffset: usize = start - rem;
            const numberOfBytesToMap: c.SIZE_T = @min(self.size - rem, len + rem);

            // pub extern fn MapViewOfFile(hFileMappingObject: HANDLE, dwDesiredAccess: DWORD, dwFileOffsetHigh: DWORD, dwFileOffsetLow: DWORD, dwNumberOfBytesToMap: SIZE_T) LPVOID;
            const ptr = c.MapViewOfFile(
                self.handle.?, // hFileMappingObject
                if (options.enableWriting) c.FILE_MAP_READ | c.FILE_MAP_WRITE else c.FILE_MAP_READ, // dwDesiredAccess
                @intCast(highOrderBits(fileOffset)), // dwFileOffsetHigh
                @intCast(lowOrderBits(fileOffset)), // dwFileOffsetLow
                numberOfBytesToMap, // dwNumberOfBytesToMap
            );

            if (ptr == null) {
                const errcode = std.os.windows.GetLastError();

                std.log.err("Map view of file failed with error code: {d} / {s}",.{@intFromEnum(errcode), @tagName(errcode)});
                return error.MapViewOfFileFailed;
            }

            var bytes: []u8 = undefined;
            bytes.ptr = @ptrFromInt(@intFromPtr(ptr.?));
            bytes.len = numberOfBytesToMap;
            bytes = bytes[rem..];
            return View{
                .baseAddress = ptr.?,
                .bytes = bytes,
            };
        }
        pub fn getSize(self: *const Self) usize {
            return self.size;
        }

        inline fn highOrderBits(input: u64) u32 {
            return @truncate(input >> 32);
        }
        inline fn lowOrderBits(input: u64) u32 {
            return @truncate(input);
        }
    };
}
