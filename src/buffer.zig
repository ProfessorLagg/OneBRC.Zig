const builtin = @import("builtin");
const std = @import("std");

pub const Buffer = @This();

pub const size: comptime_int = 8_388_608; //65536;
pub const alignment: comptime_int = 4096;

ptr: *align(alignment) [size]u8,

pub inline fn slice(self: *Buffer, len: usize) []align(alignment) u8 {
    return @as([*]align(alignment) u8, @ptrCast(self.ptr))[0..@min(size, len)];
}
pub fn create() !Buffer {
    const addr = switch (builtin.os.tag) {
        .windows => try std.os.windows.VirtualAlloc(
            null,
            // VirtualAlloc will round the length to a multiple of page size.
            // "If the lpAddress parameter is NULL, this value is rounded up to
            // the next page boundary".
            size,
            std.os.windows.MEM_COMMIT | std.os.windows.MEM_RESERVE,
            std.os.windows.PAGE_READWRITE,
        ),
        else => (try std.heap.page_allocator.alignedAlloc(u8, alignment, size)).ptr,
    };
    std.debug.assert(std.mem.isAligned(@intFromPtr(addr), alignment));

    return Buffer{ .ptr = @ptrFromInt(@intFromPtr(addr)) };
}

pub fn destroy(self: *Buffer) void {
    switch (builtin.os.tag) {
        .windows => std.os.windows.VirtualFree(self.ptr, 0, std.os.windows.MEM_RELEASE),
        else => std.heap.page_allocator.free(self.slice(size)),
    }
}
