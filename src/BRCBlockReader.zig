const builtin = @import("builtin");
const std = @import("std");
const ut = @import("utils.zig");

pub fn BRCBlockReader(comptime TReader: type, comptime BlockSize: u32) type {
    return struct {
        const Self = @This();
        const Unmanaged: type = BRCBlockReaderUnmanaged(TReader, BlockSize);

        allocator: std.mem.Allocator,
        unmanaged: Unmanaged,
        pub fn init(allocator: std.mem.Allocator, reader: TReader) Self {
            return Self{
                .allocator = allocator,
                .unmanaged = Unmanaged.init(reader),
            };
        }
        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
        }
        pub fn next(self: *Self) !?[]const u8 {
            return try self.unmanaged.next(self.allocator);
        }
    };
}

pub fn BRCBlockReaderUnmanaged(comptime TReader: type, comptime BlockSize: u32) type {
    // TODO assert reader has read method!
    return struct {
        const Self = @This();
        reader: TReader,
        remainder: []const u8 = ut.meta.zeroedSlice(u8),

        pub fn init(reader: TReader) Self {
            return Self{ .reader = reader };
        }
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.file.close();
            allocator.destroy(self.buffer);
        }

        // TODO SINCE I CAN ALWAYS READ 256 BITS FROM THE END OF THE BLOCK I CAN SIMD FIND THE END INDEX

        pub fn next(self: *Self, allocator: std.mem.Allocator) !?[]const u8 {
            const buffer: []u8 = try allocator.alloc(u8, BlockSize);
            std.debug.assert(buffer.len == BlockSize);
            const remlen: usize = self.remainder.len;
            if (remlen > 0) {
                @memcpy(buffer[0..remlen], self.remainder);
                allocator.free(self.remainder);
            }
            const read_size = try self.reader.read(buffer[remlen..]);

            var result: []const u8 = buffer[0..(remlen + read_size)];
            switch (result.len) {
                0 => return null,
                BlockSize => {
                    result.len = std.mem.lastIndexOfScalar(u8, result, '\n') orelse result.len;
                    if (result.len < BlockSize) {
                        // copy out remainder
                        var idx: usize = result.len;
                        while (idx < buffer.len and buffer[idx] == '\n') : (idx += 1) {}
                        self.remainder = try ut.mem.clone(u8, allocator, buffer[idx..]);
                    } else {
                        self.remainder.len = 0;
                        self.remainder.ptr = @ptrFromInt(@alignOf(u8));
                    }
                },
                else => std.debug.assert(result.len < buffer.len),
            }

            return result;
        }
    };
}
