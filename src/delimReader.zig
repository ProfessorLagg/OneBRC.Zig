const std = @import("std");

/// Iterator to read a file line by line
pub fn DelimReader(comptime Treader: type, comptime delim: u8, comptime buffersize: usize) type {
    return struct {
        const TSelf = @This();
        allocator: std.mem.Allocator,
        unmanaged: UnmanagedDelimReader(Treader, delim),

        pub fn init(allocator: std.mem.Allocator, reader: Treader) !TSelf {
            const buffer = try allocator.alignedAlloc(u8, 4096, buffersize);
            return TSelf{ .allocator = allocator, .unmanaged = UnmanagedDelimReader(Treader, delim).init(reader, buffer) };
        }
        pub fn deinit(self: *TSelf) void {
            self.allocator.free(self.unmanaged.buffer);
        }
        pub inline fn next(self: *TSelf) !?[]const u8 {
            return self.unmanaged.next();
        }
    };
}

/// Iterator to read a file line by line, using an externally managed buffer
pub fn UnmanagedDelimReader(comptime Treader: type, comptime delim: u8) type {
    comptime {
        if (!std.meta.hasMethod(Treader, "read")) {
            @compileError("Treader type " ++ @typeName(Treader) ++ " does not have a .read method");
        }
    }

    return struct {
        const TSelf = @This();
        reader: Treader,
        buffer: []u8,
        slice: []u8,

        pub fn init(reader: Treader, buffer: []u8) TSelf {
            var r = TSelf{
                .buffer = buffer,
                .reader = reader,
                .slice = undefined,
            };
            r.slice = r.buffer[0..0];
            return r;
        }

        /// Finds index of self.slice[0] in self.buffer
        inline fn getpos(self: *TSelf) usize {
            return @intFromPtr(self.slice.ptr) - @intFromPtr(&self.buffer[0]);
        }

        /// returns the index in self.slice of the next delimiter, otherwise null
        inline fn nextDelimIndex(self: *TSelf) ?usize {
            for (0..self.slice.len) |i| {
                if (self.slice[i] == delim) {
                    return i;
                }
            }
            return null;
        }

        pub inline fn next(self: *TSelf) !?[]const u8 {
            goto: while (true) {
                if (self.slice.len == 0) {
                    // contains no line
                    self.slice = self.buffer[0..];
                    self.slice.len = try self.reader.read(self.buffer[0..]);
                    if (self.slice.len == 0) {
                        return null;
                    }
                }
                const delim_index: usize = self.nextDelimIndex() orelse 0;
                if (delim_index == 0) {
                    // rotate buffer
                    std.mem.copyForwards(u8, self.buffer[0..], self.slice);

                    self.slice = self.buffer[0..self.slice.len];

                    const readcount = try self.reader.read(self.buffer[self.slice.len..]);
                    self.slice.len += readcount;
                    if (readcount <= 0) {
                        // return partial line
                        const result_len: usize = self.slice.len;
                        self.slice.len = 0;
                        return self.buffer[0..result_len];
                    }

                    continue :goto;
                }

                // Found full line
                const result: []const u8 = self.slice[0..delim_index];
                self.slice = self.slice[delim_index + 1 ..];
                return result;
            }
        }
    };
}

pub fn VirtualAllocDelimReader(comptime Treader: type, comptime delim: u8) type {
    const VirtualAlloc = @import("VirtualAlloc.zig");
    return struct {
        const TSelf = @This();
        unmanaged: UnmanagedDelimReader(Treader, delim),

        /// `allocator` is only here to keep the API the same as DelimReader
        pub fn init(allocator: ?std.mem.Allocator, reader: Treader) !TSelf {
            _ = &allocator;
            return @call(.always_inline, initReal, .{reader});
        }
        pub fn initReal(reader: Treader) !TSelf {
            const buffer = try VirtualAlloc.allocBlock();
            return TSelf{ .unmanaged = UnmanagedDelimReader(Treader, delim).init(reader, buffer) };
        }
        pub fn deinit(self: *TSelf) void {
            VirtualAlloc.freeBlock(self.unmanaged.buffer);
        }
        pub inline fn next(self: *TSelf) !?[]const u8 {
            return self.unmanaged.next();
        }
    };
}
