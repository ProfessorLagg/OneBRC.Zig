const std = @import("std");
const memutils = @import("utils.zig").mem;

const DynamicBuffer = @This();

allocator: std.mem.Allocator,

// TODO I could save some space since raw.ptr == used.ptr
/// Raw backing buffer
raw: []u8,
/// Slice of backing buffer that has actually been written to
used: []u8,

pub fn init(allocator: std.mem.Allocator) !DynamicBuffer {
    const init_size = std.heap.pageSize();
    const raw = try allocator.alloc(u8, init_size);
    const r: DynamicBuffer = .{
        .allocator = allocator,
        .raw = raw[0..],
        .used = raw[0..0],
    };

    std.debug.assert(r.raw.len == init_size);
    std.debug.assert(r.used.len == 0);
    return r;
}

pub fn deinit(self: *DynamicBuffer) void {
    self.allocator.free(self.raw);
}

/// Resizes the buffer if needed so that `raw.len` >= `size`
fn ensureCapacity(self: *DynamicBuffer, size: usize) !void {
    if (self.raw.len >= size) return;

    // TODO This could probably be faster by making it not use a loop
    var new_len: usize = self.raw.len;
    while (new_len < size) {
        std.debug.assert(new_len <= comptime (std.math.maxInt(usize) / 2));
        new_len *= 2;
    }

    // if (try resize(self.allocator, &self.raw, new_len)) self.used = self.raw[0..self.used.len];
    _ = try memutils.resize(u8, self.allocator, &self.raw, new_len);
    self.used = self.raw[0..self.used.len];
    std.debug.assert(self.raw.len >= size);
    std.debug.assert(self.raw.ptr == self.used.ptr);
}

/// Resizes the buffer if needed so that there is atleast `size` number of unused bytes
inline fn ensureFreeCapacity(self: *DynamicBuffer, size: usize) !void {
    try self.ensureCapacity(self.used.len + size);
    std.debug.assert(self.raw.len >= (self.used.len + size));
}

/// returns the unused part of `self.raw`
inline fn getUnused(self: *DynamicBuffer) []u8 {
    return self.raw[self.used.len..];
}

/// Writes `bytes` to then end of the buffer and returns a slice to the newly written bytes
pub fn write(self: *DynamicBuffer, bytes: []const u8) ![]u8 {
    try self.ensureFreeCapacity(bytes.len);

    const unused = self.getUnused();
    std.debug.assert(unused.len >= bytes.len);

    const clen: usize = memutils.copy(bytes, unused);
    std.debug.assert(clen == bytes.len);

    self.used.len += clen;
    const result: []u8 = self.used[(self.used.len - clen)..];
    std.debug.assert(std.mem.eql(u8, bytes, result));
    return result;
}

test write {
    const allocator: std.mem.Allocator = std.testing.allocator;
    var dynbuf: DynamicBuffer = try DynamicBuffer.init(allocator);
    defer dynbuf.deinit();

    const arr = "hello world";
    const slc: []const u8 = arr[0..];

    inline for (0..17) |_| {
        const pre_len = dynbuf.used.len;
        const pst_slc = try dynbuf.write(slc);
        const pst_len = dynbuf.used.len;

        try std.testing.expectEqual(pre_len + slc.len, pst_len);
        try std.testing.expectEqualStrings(slc, pst_slc);
    }
}
