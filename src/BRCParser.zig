const builtin = @import("builtin");
const std = @import("std");

const BRCMap = @import("brcmap.zig");
const MapVal = BRCMap.MapVal;

fn fastIntParse(comptime T: type, noalias numstr: []const u8) T {
    comptime {
        const ti: std.builtin.Type = @typeInfo(T);
        if (ti != .int) @compileError("Expected signed integer, but found " ++ @typeName(T));
        if (ti.int.signedness != .signed) @compileError("Expected signed integer, but found " ++ @typeName(T));
    }

    std.debug.assert(numstr.len > 0);
    const isNegative: bool = numstr[0] == '-';
    const isNegativeInt: T = @intFromBool(isNegative);

    var result: T = 0;
    var m: T = 1;

    var i: isize = @as(isize, @intCast(numstr.len)) - 1;
    while (i >= isNegativeInt) : (i -= 1) {
        const ci: T = @intCast(numstr[@as(usize, @bitCast(i))]);
        const valid: bool = ci >= 48 and ci <= 57;
        const validInt: T = @intFromBool(valid);
        const invalidInt: T = @intFromBool(!valid);
        result += validInt * ((ci - 48) * m); // '0' = 48
        m = (m * 10 * validInt) + (m * invalidInt);
    }

    const sign: T = (-1 * isNegativeInt) + @as(T, @intFromBool(!isNegative));
    return result * sign;
}

pub const BRCParser = @This();

allocator: std.mem.Allocator,
file: std.fs.File,
linecount: usize = 0,

pub fn init(allocator: std.mem.Allocator, path: []const u8) !BRCParser {
    return BRCParser{
        .allocator = allocator,
        .file = try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{
            .mode = .read_only,
            .allow_ctty = false,
            .lock = .none,
            .lock_nonblocking = false,
        }),
    };
}

pub fn deinit(self: *BRCParser) void {
    self.file.close();
}

pub fn parse(self: *BRCParser) !BRCMap {
    var result: BRCMap = try BRCMap.init(self.allocator);
    const backing_buffer: []u8 = try self.allocator.alloc(u8, std.heap.pageSize());
    var buffer = backing_buffer[0..];
    buffer.len = try self.file.read(backing_buffer);

    self.linecount = 0;
    while (buffer.len > 0) {
        inner: while (buffer.len > 0) {
            const split = std.mem.indexOfScalar(u8, buffer, ';') orelse {
                // TODO make sure we can exit when trailing whitespace or malformed file
                break :inner;
            };
            var end: usize = split + 1;
            while (end < buffer.len and buffer[end] != '.') : (end += 1) {}
            end += 1;
            if (end >= buffer.len) break :inner;
            const line = buffer[0 .. end + 1];

            const new_buffer_start = line.len + @intFromBool(line.len < buffer.len);
            buffer = buffer[new_buffer_start..];

            const keystr: []const u8 = line[0..split];
            const valstr: []const u8 = line[split + 1 ..];

            const valint: i32 = fastIntParse(i32, valstr);
            const valptr: *MapVal = try result.findOrInsert(keystr);
            valptr.add(valint);
            //valptr.* = .{ .sum = valptr.sum + valint, .count = valptr.count + 1 };

            self.linecount += 1;
        }

        // read more data into the buffer
        const l = buffer.len;
        std.mem.copyForwards(u8, backing_buffer, buffer);
        //@memcpy(backing_buffer[0..l], buffer);
        const readcount = try self.file.read(backing_buffer[l..]);
        buffer = backing_buffer[0 .. l + readcount];
        while (buffer.len > 0 and buffer[0] == '\n') : (buffer = buffer[1..]) {}
    }

    return result;
}
