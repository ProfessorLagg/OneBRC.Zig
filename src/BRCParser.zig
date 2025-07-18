const builtin = @import("builtin");
const std = @import("std");

const DelimReader = @import("delimReader.zig").DelimReader;
const LineReader = DelimReader(std.fs.File.Reader, '\n', 4096);
const BRCMap = @import("brcmap.zig");
const MapVal = BRCMap.MapVal;

const linelog = std.log.scoped(.Lines);

const ut = @import("utils.zig");

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
        linelog.debug("line{d}: {s}, k: {s}, v: {s}", .{ self.linecount, line, keystr, valstr });

        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        const valint: i48 = ut.math.fastIntParse(i48, valstr);
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
