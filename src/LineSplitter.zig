const builtin = @import("builtin");
const std = @import("std");

const backend_supports_vectors = switch (builtin.zig_backend) {
    .stage2_llvm, .stage2_c => true,
    else => false,
};

pub const LineSplitter = @This();
buffer: []const u8,

fn indexOfDelim(self: *const LineSplitter) ?usize {
    @setRuntimeSafety(false);
    std.debug.assert(backend_supports_vectors);
    std.debug.assert(!std.debug.inValgrind());
    std.debug.assert(!@inComptime());
    const block_len = 16;
    const slice: []const u8 = self.buffer[0..];
    var i: usize = 5;
    const Block: type = @Vector(block_len, u8);
    if (i + 2 * block_len < slice.len) {
        const mask: Block = @splat('\n');
        while (true) {
            inline for (0..2) |_| {
                const block: Block = slice[i..][0..block_len].*;
                const matches = block == mask;
                if (@reduce(.Or, matches)) {
                    return i + std.simd.firstTrue(matches).?;
                }
                // if (std.simd.firstTrue(matches)) |I| return i + I;
                i += block_len;
            }
            if (i + 2 * block_len >= slice.len) break;
        }
    }
    
    inline for (0..2) |j| {
        const block_x_len = block_len / (1 << j);
        comptime if (block_x_len < 4) break;

        const BlockX = @Vector(block_x_len, u8);
        if (i + block_x_len < slice.len) {
            const mask: BlockX = @splat('\n');
            const block: BlockX = slice[i..][0..block_x_len].*;
            const matches = block == mask;
            if (@reduce(.Or, matches)) {
                return i + std.simd.firstTrue(matches).?;
            }
            // if (std.simd.firstTrue(matches)) |I| return i + I;
            i += block_x_len;
        }
    }

    for (slice[i..], i..) |c, j| {
        if (c == '\n') return j;
    }
    return null;
}
pub fn next(self: *LineSplitter) ?[]const u8 {
    if (self.buffer.len == 0) return null;
    // TODO i can optimize this better because i know the delimiter at comptime
    // const si: usize = std.mem.indexOfScalarPos(u8, self.buffer, 5, '\n') orelse self.buffer.len;
    const si: usize = self.indexOfDelim() orelse self.buffer.len;
    const result: []const u8 = self.buffer[0..si];
    self.buffer = self.buffer[@min(self.buffer.len, si + 1)..];
    return result;
}
