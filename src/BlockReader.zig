const builtin = @import("builtin");
const std = @import("std");
const fileMapping = @import("fileMapping.zig");
const MappedFile = @import("fileMapping.zig").MappedFile;

pub fn BlockReader(
    /// Maximum size of the blocks
    comptime blocksize: comptime_int,
    /// Delimiter to split the blocks on
    comptime delimiter: u8,
) type {
    return struct {
        const Self = @This();
        mappedFile: MappedFile,
        left: u64,

        pub fn init(path: []const u8) !Self {
            return Self{ .mappedFile = try fileMapping.map(path), .left = 0 };
        }

        pub fn deinit(self: *Self) void {
            fileMapping.unmap(self.mappedFile);
        }

        /// reads the next block if possible
        pub fn next(self: *Self) ?[]const u8 {
            const FileLength = self.mappedFile.slice.len;
            if (self.left < FileLength) {
                var length: usize = 0;
                var right: usize = self.left + blocksize;
                const offset: usize = self.left;
                if (right >= FileLength) {
                    length = FileLength - self.left;
                    self.left = FileLength + 1;
                } else {
                    while (self.mappedFile.slice[right] != delimiter) right -= 1;
                    length = right - self.left;
                    self.left = right + 1;
                }
                return self.mappedFile.slice[offset..(offset + length)];
            }
            return null;
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
