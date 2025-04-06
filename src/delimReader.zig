const std = @import("std");
const log = std.log.scoped(.DelimReader);
const utils = @import("utils.zig");

/// Iterator to read a file line by line
pub fn DelimReader(comptime Treader: type, comptime delim: u8, comptime buffersize: usize) type {
    comptime {
        if (!std.meta.hasMethod(Treader, "read")) {
            @compileError("Treader type " ++ @typeName(Treader) ++ " does not have a .read method");
        }
    }

    return struct {
        const TSelf = @This();
        allocator: std.mem.Allocator,
        reader: Treader,
        buffer: []u8,
        slice: []u8,

        pub fn init(allocator: std.mem.Allocator, reader: Treader) !TSelf {
            log.debug("DelimReader" ++
                "\n\t" ++ "Treader: " ++ "{s}" ++
                "\n\t" ++ "delim: {d} | 0x{X:0>2}" ++
                "\n\t" ++ "buffer size: {d}" ++ "\n", .{ @typeName(Treader), delim, delim, buffersize });
            var r = TSelf{ // NO FOLD
                .allocator = allocator,
                .buffer = try allocator.alloc(u8, buffersize),
                .reader = reader,
                .slice = undefined,
            };
            r.slice = r.buffer[0..];
            r.slice.len = r.reader.read(r.buffer) catch |err| {
                allocator.free(r.buffer);
                return err;
            };
            return r;
        }

        pub fn deinit(self: *TSelf) void {
            self.allocator.free(self.buffer);
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
                    log.debug("DelimReader: NONE", .{});
                    self.slice = self.buffer[0..];
                    self.slice.len = try self.reader.read(self.buffer[0..]);
                    if (self.slice.len == 0) {
                        return null;
                    }
                }
                const delim_index: usize = self.nextDelimIndex() orelse 0;
                if (delim_index == 0) {
                    // Contains partial line
                    log.debug("DelimReader: PART", .{});
                    // rotate buffer
                    utils.mem.copyForwards(u8, self.buffer[0..], self.slice);

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
                log.debug("DelimReader: FULL", .{});
                const result: []const u8 = self.slice[0..delim_index];
                self.slice = self.slice[delim_index + 1 ..];
                return result;
            }
        }
    };
}
