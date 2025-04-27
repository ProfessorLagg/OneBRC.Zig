const std = @import("std");

pub const ProgressiveFileReader = @This();

const block_size = 4096;
allocator: std.mem.Allocator,

file: std.fs.File,

buffer: []u8,
data: []const u8,
isReading: bool = false,

pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !ProgressiveFileReader {
    const stat = try file.stat();
    var r: ProgressiveFileReader = ProgressiveFileReader{
        .allocator = allocator,
        .file = file,
        .buffer = try allocator.alloc(u8, stat.size),
        .data = undefined,
    };
    r.data = r.buffer[0..0];
    return r;
}
pub fn deinit(self: *ProgressiveFileReader) void {
    self.allocator.free(self.buffer);
}

fn readBlock(self: *ProgressiveFileReader) !usize {
    const L: usize = self.data.len;
    const R: usize = @min(self.buffer.len, L + block_size);
    const slice: []u8 = self.buffer[L..R];
    const r: usize = try self.file.read(slice);
    self.data.len += r;
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
    self.read() catch {
        @panic("Reading file failed!");
    };
}
