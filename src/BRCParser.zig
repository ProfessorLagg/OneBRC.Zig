const builtin = @import("builtin");
const std = @import("std");

const DelimReader = @import("delimReader.zig").DelimReader;
const LineReader = DelimReader(std.fs.File.Reader, '\n', 1024 * 128);
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
    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    self.linecount = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        const keystr: []const u8 = line[0..splitIndex];
        const valstr: []const u8 = line[(splitIndex + 1)..];
        std.log.debug("line{d}: {s}, k: {s}, v: {s}", .{ self.linecount, line, keystr, valstr });

        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        const valint: i32 = fastIntParse(i32, valstr);
        const valptr: *MapVal = try result.findOrInsert(keystr);
        valptr.add(valint);
        self.linecount += 1;
    }
    return result;
}

pub fn read(self: *BRCParser) !BRCMap {
    const result: BRCMap = try BRCMap.init(self.allocator);
    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    self.linecount = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        self.linecount += 1;
    }
    return result;
}
