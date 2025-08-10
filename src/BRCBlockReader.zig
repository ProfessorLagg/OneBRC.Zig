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

        /// Split's the input buffer on the last `\n`.
        /// Updates buffer.len to not include the last `\n`
        /// Returns the remaning bytes, excluding the last `\n`
        fn splitBuffer(buffer: *[]u8) []const u8 {
            std.debug.assert(buffer.len == BlockSize);
            const full_buffer: []const u8 = buffer.*[0..buffer.len];
            var split_index = buffer.len - 100;
            while (split_index < buffer.len and buffer.ptr[split_index] != '\n') {
                split_index += 1;
            }
            buffer.len = split_index;
            return if (split_index >= full_buffer.len) ut.meta.zeroedSlice(u8) else full_buffer[split_index + 1 ..];
        }
        pub fn next(self: *Self, allocator: std.mem.Allocator) !?[]const u8 {
            var block: []u8 = try allocator.alloc(u8, BlockSize);
            @memset(block, 0);
            if (self.remainder.len > 0) { // Copy out the previous remaining bytes
                _ = ut.mem.copy(u8, self.remainder, @constCast(block[0..self.remainder.len]));
                allocator.free(self.remainder);
                self.remainder.ptr = @ptrFromInt(@alignOf(u8));
                self.remainder.len = 0;
            }

            const writeable_buffer: []u8 = @constCast(block[self.remainder.len..]);
            const read_size = try self.reader.read(writeable_buffer);
            block.len = self.remainder.len + read_size;
            if (block.len == 0 or block[0] == 0) return null;
            if (block.len == BlockSize) {
                const new_remainder = splitBuffer(&block);
                self.remainder = try ut.mem.clone(u8, allocator, new_remainder);
            }
            return block;
        }
    };
}
