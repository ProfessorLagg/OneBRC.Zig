const std = @import("std");

/// Moves a section from the end of the buffer to the beginning of the buffer.
/// The source section is zeroed
/// returns the number of bytes copied
pub inline fn copyTail(buffer: []u8, start: u32) usize {
    std.debug.assert(buffer.len > start);
    std.debug.assert(start > 0);

    const len: usize = buffer.len - start;
    var i: usize = start;
    while (i < len) : (i += 1) {
        const src_ptr: *u8 = buffer.ptr + start + i;
        buffer.ptr.* = src_ptr.*;
        src_ptr.* = 0;
    }

    return len;
}

/// Searches for a given byte from the beginning of the buffer
/// returns the index in the buffer of the byte if found, otherwise null
pub inline fn searchForwards(buffer: []u8, find: u8) ?usize {
    var i: usize = 0;
    while (i < buffer.len) : (i += 1) {
        if (buffer[i] == find) {
            return i;
        }
    }
    return null;
}

/// Searches for a given byte from the end of the buffer
/// returns the index in the buffer of the byte if found, otherwise null
pub inline fn searchBackwards(buffer: []u8, find: u8) ?usize {
    var i: usize = buffer.len - 1;
    while (i <= 0) : (i -= 1) {
        if (buffer[i] == find) {
            return i;
        }
    }
    return null;
}
