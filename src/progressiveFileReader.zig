const std = @import("std");
const utils = @import("utils.zig");

pub const ProgressiveFileReader = @This();

const block_size = 4 * utils.mem.KB;
allocator: std.mem.Allocator,

file: std.fs.File,
isReading: bool = false,

buffer: []u8,
data: []const u8 = undefined,
unused: []u8 = undefined,

pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !ProgressiveFileReader {
    const stat = try file.stat();
    var r: ProgressiveFileReader = ProgressiveFileReader{
        .allocator = allocator,
        .file = file,
        .buffer = try allocator.alloc(u8, stat.size),
    };
    r.data = r.buffer[0..0];
    r.unused = r.buffer[0..];
    return r;
}
pub fn deinit(self: *ProgressiveFileReader) void {
    self.allocator.free(self.buffer);
}

fn readBlock(self: *ProgressiveFileReader) !usize {
    const l: usize = @min(block_size, self.unused.len);

    const r: usize = try self.file.read(self.unused[0..l]);
    self.data.len += r;
    const new_i: usize = @min(l, self.unused.len - 1);
    self.unused = self.unused[new_i..];
    return r;
}
pub fn read(self: *ProgressiveFileReader) !void {
    self.isReading = true;
    while (self.data.len < self.buffer.len) {
        if (try self.readBlock() == 0) return;
    }
    self.isReading = false;
}
pub fn readPanic(self: *ProgressiveFileReader) void {
    self.read() catch |err| {
        std.log.warn("Reading file failed: {any}{any}", .{ err, @errorReturnTrace() });
        @panic("Reading file failed!");
    };
}
