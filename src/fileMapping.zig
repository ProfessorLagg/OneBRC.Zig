const builtin = @import("builtin");
const std = @import("std");
const c = @import("cImport.zig");

const fs = std.fs;
const File = fs.File;

const page_size_min: usize = std.heap.page_size_min;

const hidden_allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    break :b std.heap.page_allocator;
};

pub const MappedFile = struct {
    extra: ?*anyopaque = null,
    slice: []const u8,

    pub fn init(path: []const u8) !MappedFile {
        return map(path);
    }

    pub fn deinit(self: *MappedFile) void {
        unmap(self.*);
    }
};

pub fn map(path: []const u8) !MappedFile {
    return switch (builtin.target.os.tag) {
        .windows => try _Windows.map(path),
        .linux => try _Linux.map(path),
        else => unreachable,
    };
}
pub fn unmap(mappedFile: MappedFile) void {
    switch (builtin.target.os.tag) {
        .windows => _Windows.unmap(mappedFile),
        .linux => _Linux.unmap(mappedFile),
        else => unreachable,
    }
}

const _Windows = struct {
    const MappedFileInfo = struct {
        file: std.fs.File = undefined,
        hMap: c.HANDLE = null,
        hView: c.HANDLE = null,

        fn init(path: []const u8) !*MappedFileInfo {
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
        var slice: []const u8 = undefined;
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
        hidden_allocator.destroy(mfi);
    }
};

const _Linux = struct {
    fn map(path: []const u8) !MappedFile {
        const file: *File = try hidden_allocator.create(File);
        file.* = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        const file_len: u64 = file.*.getEndPos() catch (file.stat() catch unreachable).size;
        const mapped_mem = try std.posix.mmap(
            null,
            file_len,
            std.c.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        return MappedFile{
            .extra = file,
            .slice = mapped_mem[0..],
        };
    }
    fn unmap(mappedFile: MappedFile) void {
        const mem: []align(page_size_min) const u8 = @alignCast(mappedFile.slice);
        std.posix.munmap(mem);
        const file: *align(1) File = @ptrCast(mappedFile.extra);
        file.*.close();
        hidden_allocator.destroy(file);
    }
};
