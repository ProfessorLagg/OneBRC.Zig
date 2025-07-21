const builtin = @import("builtin");
const std = @import("std");
const StringHashMap = std.StringHashMap;

const DelimReader = @import("delimReader.zig").DelimReader;
const LineReader = DelimReader(std.fs.File.Reader, '\n', 4096);
const BRCBucketMap = @import("BRCBucketMap.zig").BRCBucketMap;
const BRCMap = @import("BRCmap.zig");
const MapVal = BRCMap.MapVal;
const MapEntry = BRCMap.MapEntry;
const ut = @import("utils.zig");
const linelog = std.log.scoped(.Lines);

pub const BRCParseResult = struct {
    pub const ResultEntry = struct {
        key: []const u8,
        val: MapVal,
    };
    allocator: std.mem.Allocator,
    linecount: usize = 0,

    entries: []const ResultEntry,

    pub fn deinit(self: *BRCParseResult) void {
        for (self.entries) |e| self.allocator.free(e.key);
        self.allocator.free(self.entries);
    }

    fn init_BRCMap(linecount: usize, map: *const BRCMap) !BRCParseResult {
        const allocator: std.mem.Allocator = map.allocator;
        const entries: []ResultEntry = try allocator.alloc(ResultEntry, map.count());
        var iter = map.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            entries[i].val = entry.val.*;
            entries[i].key = try ut.mem.clone(u8, allocator, entry.key);
        }

        return BRCParseResult{
            .allocator = allocator,
            .linecount = linecount,
            .entries = entries,
        };
    }

    fn init_StringHashMap(linecount: usize, map: *StringHashMap(MapVal)) !BRCParseResult {
        const allocator: std.mem.Allocator = map.allocator;
        const entries: []ResultEntry = try allocator.alloc(ResultEntry, map.count());
        var iter = map.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            entries[i].val = entry.value_ptr.*;
            entries[i].key = try ut.mem.clone(u8, allocator, entry.key_ptr.*);
        }
        return BRCParseResult{
            .allocator = allocator,
            .linecount = linecount,
            .entries = entries,
        };
    }
};

pub const BRCParser = @This();

allocator: std.mem.Allocator,
file: std.fs.File,

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

fn parse_BRCMap(self: *BRCParser) !BRCParseResult {
    const init_capacity: usize = std.math.divCeil(usize, (try self.file.stat()).size, 14) catch unreachable;
    var map: BRCMap = try BRCMap.initCapacity(self.allocator, init_capacity);
    defer map.deinit();
    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var linecount: usize = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        const keystr: []const u8 = line[0..splitIndex];
        std.debug.assert(keystr[keystr.len - 1] != '\n');
        const valstr: []const u8 = line[(splitIndex + 1)..];
        linelog.debug("line{d}: {s}, k: {s}, v: {s}", .{ linecount, line, keystr, valstr });

        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        const valint: i48 = ut.math.fastIntParse(i48, valstr);
        const valptr: *MapVal = try map.findOrInsert(keystr);
        valptr.add(valint);
        linecount += 1;
    }

    return BRCParseResult.init_BRCMap(linecount, &map);
}

fn parse_BRCBucketMap(self: *BRCParser) !BRCParseResult {
    const bucket_count: comptime_int = 512;
    const init_capacity: usize = std.math.divCeil(usize, (try self.file.stat()).size, 14 * bucket_count) catch unreachable;
    var bucketMap: BRCBucketMap(bucket_count) = try BRCBucketMap(bucket_count).initCapacity(self.allocator, init_capacity);

    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var linecount: usize = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        const keystr: []const u8 = line[0..splitIndex];
        std.debug.assert(keystr[keystr.len - 1] != '\n');
        const valstr: []const u8 = line[(splitIndex + 1)..];
        linelog.debug("line{d}: {s}, k: {s}, v: {s}", .{ linecount, line, keystr, valstr });

        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        const valint: i48 = ut.math.fastIntParse(i48, valstr);
        //const map = bucketMap.findBucket(keystr);
        //const valptr: *MapVal = try map.findOrInsert(keystr);
        const valptr: *MapVal = try bucketMap.findOrInsert(keystr);
        valptr.add(valint);
        linecount += 1;
    }

    const finalMap: BRCMap = try bucketMap.finalize(self.allocator);
    return BRCParseResult.init_BRCMap(linecount, &finalMap);
}

fn parse_StringHashMap(self: *BRCParser) !BRCParseResult {
    var map: StringHashMap(MapVal) = std.StringHashMap(MapVal).init(self.allocator);
    defer map.deinit();

    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var linecount: usize = 0;
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        var splitIndex: usize = line.len - 4;
        while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
        std.debug.assert(line[splitIndex] == ';');

        const keystr: []const u8 = line[0..splitIndex];
        const valstr: []const u8 = line[(splitIndex + 1)..];
        linelog.debug("line{d}: {s}, k: {s}, v: {s}", .{ linecount, line, keystr, valstr });

        std.debug.assert(keystr.len >= 1);
        std.debug.assert(keystr.len <= 100);
        std.debug.assert(keystr[keystr.len - 1] != ';');
        std.debug.assert(valstr.len >= 3);
        std.debug.assert(valstr.len <= 5);
        std.debug.assert(valstr[valstr.len - 2] == '.');
        std.debug.assert(valstr[0] != ';');

        const valint: i48 = ut.math.fastIntParse(i48, valstr);

        const keystr_clone = try ut.mem.clone(u8, self.allocator, keystr);
        defer self.allocator.free(keystr_clone);

        const entry = try map.getOrPut(keystr_clone);
        std.debug.assert(ut.mem.eqlBytes(keystr_clone, entry.key_ptr.*));
        if (!entry.found_existing) entry.value_ptr.* = MapVal.Zero;
        entry.value_ptr.add(valint);

        linecount += 1;
    }

    return BRCParseResult.init_StringHashMap(linecount, &map);
}

pub fn parse(self: *BRCParser) !BRCParseResult {
    // return self.parse_BRCMap();
    return self.parse_BRCBucketMap();
    // return self.parse_StringHashMap();
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
