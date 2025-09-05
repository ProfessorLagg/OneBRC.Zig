const builtin = @import("builtin");
const std = @import("std");
const fileMapping = @import("fileMapping.zig");
const MappedFile = @import("fileMapping.zig").MappedFile;

pub fn MappedFileBlockReader(
    /// Maximum size of the blocks
    comptime blocksize: comptime_int,
    /// Delimiter to split the blocks on
    comptime delimiter: u8,
) type {
    return struct {
        const Self = @This();
        mappedFile: MappedFile,
        blockReader: BlockReader(blocksize, delimiter),

        pub fn init(path: []const u8) !Self {
            const mappedFile = try MappedFile.init(path);
            return Self{
                .mappedFile = mappedFile,
                .blockReader = BlockReader(blocksize, delimiter).init(mappedFile.slice),
            };
        }

        pub fn deinit(self: *Self) void {
            fileMapping.unmap(self.mappedFile);
        }

        /// reads the next block if possible
        pub fn next(self: *Self) ?[]const u8 {
            return self.blockReader.next();
        }

        /// remaining size not yet read from the mapped file
        pub fn remain(self: *const Self) usize {
            return self.mappedFile.slice.len - @min(self.left, self.mappedFile.slice.len);
        }

        /// size of the mapped file being read
        pub inline fn fileSize(self: *const Self) usize {
            return self.mappedFile.slice.len;
        }
    };
}

pub fn BlockReader(
    /// Maximum size of the blocks
    comptime blocksize: comptime_int,
    /// Delimiter to split the blocks on
    comptime delimiter: u8,
) type {
    return struct {
        const Self = @This();
        buffer: []const u8,
        left: u64 = 0,

        pub fn init(buffer: []const u8) Self {
            return Self{ .buffer = buffer, .left = 0 };
        }

        /// reads the next block if possible
        pub fn next(self: *Self) ?[]const u8 {
            if (self.left < self.buffer.len) {
                var length: usize = 0;
                var right: usize = self.left + blocksize;
                const offset: usize = self.left;
                if (right >= self.buffer.len) {
                    length = self.buffer.len - self.left;
                    self.left = self.buffer.len + 1;
                } else {
                    while (self.buffer[right] != delimiter) right -= 1;
                    length = right - self.left;
                    self.left = right + 1;
                }
                return self.buffer[offset..(offset + length)];
            }
            return null;
        }

        /// remaining size not yet read from the mapped file
        pub fn remain(self: *const Self) usize {
            return self.buffer.len - @min(self.left, self.buffer.len);
        }
    };
}
