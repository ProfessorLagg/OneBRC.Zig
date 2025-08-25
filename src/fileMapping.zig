const builtin = @import("builtin");
const std = @import("std");
const c = @import("cImport.zig");

const fs = std.fs;
const File = fs.File;

pub const MappedFile = struct {
    extra: ?*anyopaque = null,
    slice: []u8,
};

pub fn map(path: []const u8) !MappedFile {
    return switch (builtin.target.os.tag) {
        .windows => try _Windows.map(path),
        .linux => try _Posix.map(path),
        else => unreachable,
    };
}
pub fn unmap(mappedFile: MappedFile) void {
    switch (builtin.target.os.tag) {
        .windows => _Windows.unmap(mappedFile),
        .linux => _Posix.unmap(mappedFile),
        else => unreachable,
    }
}

const _Windows = struct {
    const hidden_allocator: std.mem.Allocator = std.heap.page_allocator;

    const MappedFileInfo = struct {
        file: std.fs.File = undefined,
        hMap: c.HANDLE = null,
        hView: c.HANDLE = null,

        pub fn init(path: []const u8) !*MappedFileInfo {
            var r: *MappedFileInfo = try hidden_allocator.create(MappedFileInfo);
            r.file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
            r.hMap = c.CreateFileMappingW(
                r.file.handle, // hFile
                null, // lpFileMappingAttributes
                c.PAGE_READONLY,
                0, // dwMaximumSizeHigh
                0, // dwMaximumSizeLow
                null, // lpName
            );
            r.hView = c.MapViewOfFile(
                r.hMap, // hFileMappingObject
                c.FILE_MAP_READ, // dwDesiredAccess
                0, // dwFileOffsetHigh
                0, // dwFileOffsetLow
                0, // dwNumberOfBytesToMap
            );
            return r;
        }
    };

    fn map(path: []const u8) !MappedFile {
        const mfi: *MappedFileInfo = try MappedFileInfo.init(path);
        var slice: []u8 = undefined;
        slice.ptr = @alignCast(@ptrCast(mfi.hView));
        slice.len = (try mfi.file.stat()).size;
        return MappedFile{
            .extra = mfi,
            .slice = slice,
        };
    }

    pub fn unmap(mappedFile: MappedFile) void {
        const mfi: *align(1) MappedFileInfo = @ptrCast(mappedFile.extra);
        _ = c.UnmapViewOfFile(mfi.hView);
        std.os.windows.CloseHandle(mfi.hMap.?);
        mfi.file.close();
    }
};

const _Posix = struct {
    fn map(path: []const u8) !MappedFile {
        _ = &path;
        @compileError("Not yet implemented");
    }
    fn unmap(mappedFile: MappedFile) !void {
        _ = &mappedFile;
        @compileError("Not yet implemented");
    }
};
