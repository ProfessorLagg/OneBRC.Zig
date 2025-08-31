const builtin = @import("builtin");
const std = @import("std");

const backend_supports_vectors = switch (builtin.zig_backend) {
    .stage2_llvm, .stage2_c => true,
    else => false,
};

pub const LineSplitter = @This();
buffer: []const u8,
pub fn next(self: *LineSplitter) ?[]const u8 {
    if (self.buffer.len == 0) return null;
    // TODO i can optimize this better because i know the delimiter at comptime
    const si: usize = std.mem.indexOfScalar(u8, self.buffer, '\n') orelse self.buffer.len;
    const result: []const u8 = self.buffer[0..si];
    // TODO i can probably set the result to more than si + 1 since i know theres some minimum amount of bytes before the next \n
    self.buffer = self.buffer[@min(self.buffer.len, si + 1)..];
    return result;
}
