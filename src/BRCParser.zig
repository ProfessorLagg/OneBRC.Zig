const builtin = @import("builtin");
const std = @import("std");

// const LineReader = DelimReader(std.fs.File.Reader, '\n', 4096);
const LineReader = switch (builtin.os.tag) {
    .windows => @import("delimReader.zig").VirtualAllocDelimReader(std.fs.File.Reader, '\n'),
    else => @import("delimReader.zig").DelimReader(std.fs.File.Reader, '\n', 1_073_741_824),
};
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

        pub fn compare_order(a: *const ResultEntry, b: *const ResultEntry) std.math.Order {
            const aK: []const u8 = a.key;
            const bK: []const u8 = b.key;
            const l: usize = @min(aK.len, bK.len);
            for (0..l) |i| {
                if (aK[i] < bK[i]) return .gt;
                if (aK[i] > bK[i]) return .lt;
            }
            if (aK.len < bK.len) return .lt;
            if (aK.len > bK.len) return .gt;
            return .eq;
        }
        pub fn lessThan(ctx: @TypeOf(.{}), a: ResultEntry, b: ResultEntry) bool {
            _ = ctx;
            return compare_order(&a, &b) == .lt;
        }
    };
    allocator: std.mem.Allocator = undefined,
    linecount: usize = 0,

    entries: []const ResultEntry = ut.meta.zeroedSlice(ResultEntry),

    pub fn deinit(self: *BRCParseResult) void {
        for (self.entries) |e| self.allocator.free(e.key);
        self.allocator.free(self.entries);
    }

    fn sortEntries(entries: []ResultEntry) void {
        var i: usize = 1;
        while(i < entries.len): (i += 1){
            const x: ResultEntry = entries[i];
            var j: usize = i;
            while(j > 0 and (ResultEntry.compare_order(&entries[j - 1], &x)) == .gt):(j -= 1){
                entries[j] = entries[j - 1];
            }
            entries[j] = x;
        }
    }

    fn init(linecount: usize, map: *const BRCMap) !BRCParseResult {
        const allocator: std.mem.Allocator = map.allocator;
        const entryCount = map.sub8.count() + map.sub16.count() + map.sub32.count() + map.sub64.count() + map.sub128.count();
        const entries: []ResultEntry = try allocator.alloc(ResultEntry, entryCount);
        var entryIndex: usize = 0;
        for (0..map.sub8.count()) |i| {
            entries[entryIndex].val = map.sub8.vals[i];
            entries[entryIndex].key = try ut.mem.clone(u8, allocator, map.sub8.keys[i].asSlice());
            entryIndex += 1;
        }
        for (0..map.sub16.count()) |i| {
            entries[entryIndex].val = map.sub16.vals[i];
            entries[entryIndex].key = try ut.mem.clone(u8, allocator, map.sub16.keys[i].asSlice());
            entryIndex += 1;
        }
        for (0..map.sub32.count()) |i| {
            entries[entryIndex].val = map.sub32.vals[i];
            entries[entryIndex].key = try ut.mem.clone(u8, allocator, map.sub32.keys[i].asSlice());
            entryIndex += 1;
        }
        for (0..map.sub64.count()) |i| {
            entries[entryIndex].val = map.sub64.vals[i];
            entries[entryIndex].key = try ut.mem.clone(u8, allocator, map.sub64.keys[i].asSlice());
            entryIndex += 1;
        }
        for (0..map.sub128.count()) |i| {
            entries[entryIndex].val = map.sub128.vals[i];
            entries[entryIndex].key = try ut.mem.clone(u8, allocator, map.sub128.keys[i].asSlice());
            entryIndex += 1;
        }
        sortEntries(entries);
        

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

    return BRCParseResult.init(linecount, &map);
}

fn parse_BRCBucketMap_SingleThread(self: *BRCParser) !BRCParseResult {
    const bucket_count: comptime_int = 512;
    const BucketMap = BRCBucketMap(bucket_count);
    var bucketMap: BucketMap = try BucketMap.init(self.allocator);

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
        const valptr: *MapVal = try bucketMap.findOrInsert(keystr);
        valptr.add(valint);
        linecount += 1;
    }

    const finalMap: BRCMap = try bucketMap.finalize(self.allocator);
    return BRCParseResult.init(linecount, &finalMap);
}

fn parse_BRCBucketMap_MultiThread(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = std.Thread.Mutex;
    const ArenaAllocator = std.heap.ArenaAllocator;
    const bucket_count: comptime_int = 512;
    const BucketMap = BRCBucketMap(bucket_count);

    const buffer: []u8 = try self.allocator.alignedAlloc(u8, 4096, 65535);
    defer self.allocator.free(buffer);

    var pool: ThreadPool = undefined;
    {
        try pool.init(.{ .allocator = self.allocator });
    }

    // shared context
    const SharedContext = struct {
        const Tsctx = @This();
        allocator: std.mem.Allocator = undefined,
        linecount: usize = 0,
        map: BucketMap = undefined,
        linecount_lock: Mutex = .{},
        waitGroup: WaitGroup = .{},

        fn init(allocator: std.mem.Allocator) !*Tsctx {
            const r: *Tsctx = try allocator.create(Tsctx);
            r.*.allocator = allocator;
            r.*.linecount = 0;
            r.*.map = try BucketMap.init(allocator);

            r.*.linecount_lock = .{};
            r.*.waitGroup = .{};
            return r;
        }
        fn deinit(sctx: *Tsctx) void {
            sctx.map.deinit();
            sctx.allocator.destroy(sctx);
        }
    };
    // Gotta put anything that touches a thread on the heap
    const sharedContext: *SharedContext = try SharedContext.init(self.allocator); //self.allocator.create();
    defer sharedContext.deinit();

    const TaskContext = struct {
        const Tctx = @This();
        shared: *SharedContext,
        arena: ArenaAllocator,
        block: []const u8,
        blockId: usize,

        fn run(ctx: *Tctx) void {
            defer ctx.deinit();
            var lineIter = std.mem.splitScalar(u8, ctx.block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| {
                std.debug.assert(line.len >= 5);
                var splitIndex: usize = line.len - 4;
                while (line[splitIndex] != ';' and splitIndex > 0) : (splitIndex -= 1) {}
                std.debug.assert(line[splitIndex] == ';');

                const keystr: []const u8 = line[0..splitIndex];
                std.debug.assert(keystr[keystr.len - 1] != '\n');
                const valstr: []const u8 = line[(splitIndex + 1)..];

                std.debug.assert(keystr.len >= 1);
                std.debug.assert(keystr.len <= 100);
                std.debug.assert(keystr[keystr.len - 1] != ';');
                std.debug.assert(valstr.len >= 3);
                std.debug.assert(valstr.len <= 5);
                std.debug.assert(valstr[valstr.len - 2] == '.');
                std.debug.assert(valstr[0] != ';');

                const valint: i48 = ut.math.fastIntParse(i48, valstr);
                ctx.shared.map.findOrAdd(keystr, valint) catch |e| {
                    ut.debug.print("\n{any}\n{any}\n", .{ e, @errorReturnTrace() });
                    @panic("BucketMap.findOrAdd failed");
                };
                localCount += 1;
            }

            ctx.shared.linecount_lock.lock();
            ctx.shared.linecount += localCount;
            ctx.shared.linecount_lock.unlock();
        }

        fn deinit(ctx: *Tctx) void {
            ctx.arena.deinit();
        }

        fn spawn(shared: *SharedContext, threadPool: *ThreadPool, rawBytes: []const u8, id: usize) !void {
            var arena = ArenaAllocator.init(shared.allocator);
            const allocator = arena.allocator();

            const ctx: *Tctx = try allocator.create(Tctx);
            ctx.*.shared = shared;
            ctx.*.arena = arena;
            ctx.*.block = try ut.mem.clone(u8, allocator, rawBytes);
            ctx.blockId = id;
            threadPool.spawnWg(&shared.waitGroup, run, .{ctx});
        }
    };

    var readSize: usize = try self.file.read(buffer);
    var bytes: []const u8 = buffer[0..readSize];
    var blockCount: usize = 0;
    while (readSize > 0) {
        blockCount += 1;

        // Find end of the last line in the buffer
        const endIndex = lastLineEndIndex(bytes);
        var remain = buffer[@min(buffer.len, endIndex + 2)..];
        while (remain.len > 0 and remain[0] == '\n') : (remain = remain[1..]) {}
        while (remain.len > 0 and remain[remain.len - 1] == '\n') : (remain.len -= 1) {}
        bytes = bytes[0 .. endIndex + 1];

        // ut.debug.print("=== BUFFER\n\"{s}\"\n=== BYTES\n\"{s}\"\n=== REMAIN\n\"{s}\"\n===      \n", .{ buffer, bytes, remain });

        // Schedule a thread to parse the buffer
        try TaskContext.spawn(sharedContext, &pool, bytes, blockCount);

        // once the task is spawned i can mock about with bytes again to read more data from the file
        std.mem.copyForwards(u8, buffer, remain);
        readSize = try self.file.read(buffer[remain.len..]);
        bytes = buffer[@intFromBool(buffer[0] == '\n') .. readSize + remain.len];
    }

    sharedContext.waitGroup.wait();

    const finalMap: BRCMap = try sharedContext.map.finalize(self.allocator);
    return BRCParseResult.init(sharedContext.linecount, &finalMap);
}

pub fn parse(self: *BRCParser) !BRCParseResult {
    const parseFn = comptime switch (builtin.single_threaded) {
        true => parse_BRCBucketMap_SingleThread,
        false => parse_BRCBucketMap_MultiThread,
    };
    return parseFn(self);
}

fn read_SingleThread(self: *BRCParser) !BRCParseResult {
    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var result: BRCParseResult = .{};
    while (try lineReader.next()) |line| {
        std.debug.assert(line.len >= 5);
        result.linecount += 1;
    }
    return result;
}

fn read_MultiThread(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = std.Thread.Mutex;
    const ArenaAllocator = std.heap.ArenaAllocator;

    const buffer: []u8 = try self.allocator.alignedAlloc(u8, 4096, 65535);
    defer self.allocator.free(buffer);

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });

    const SharedContext = struct {
        allocator: std.mem.Allocator = undefined,
        result: BRCParseResult = .{},
        result_lock: Mutex = .{},
        waitGroup: WaitGroup = .{},
    };
    // Gotta put anything that touches a thread on the heap
    const sharedContext: *SharedContext = try self.allocator.create(SharedContext);
    defer self.allocator.destroy(sharedContext);
    sharedContext.*.allocator = self.allocator;
    sharedContext.*.result = .{};
    sharedContext.*.result_lock = .{};
    sharedContext.*.waitGroup = .{};

    const TaskContext = struct {
        const Tctx = @This();
        shared: *SharedContext,
        arena: ArenaAllocator,
        block: []const u8,
        blockId: usize,

        fn run(ctx: *Tctx) void {
            defer ctx.deinit();
            var lineIter = std.mem.splitScalar(u8, ctx.block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| {
                _ = &line;
                localCount += 1;
            }

            ctx.shared.result_lock.lock();
            ctx.shared.result.linecount += localCount;
            ctx.shared.result_lock.unlock();
        }

        fn deinit(ctx: *Tctx) void {
            ctx.arena.deinit();
        }
        fn spawn(shared: *SharedContext, threadPool: *ThreadPool, rawBytes: []const u8, id: usize) !void {
            var arena = ArenaAllocator.init(shared.allocator);
            const allocator = arena.allocator();

            const ctx: *Tctx = try allocator.create(Tctx);
            ctx.*.shared = shared;
            ctx.*.arena = arena;
            ctx.*.block = try ut.mem.clone(u8, allocator, rawBytes);
            ctx.blockId = id;
            threadPool.spawnWg(&shared.waitGroup, run, .{ctx});
        }
    };

    var readSize: usize = try self.file.read(buffer);
    var bytes: []const u8 = buffer[0..readSize];
    var blockCount: usize = 0;
    while (readSize > 0) {
        blockCount += 1;

        // Find end of the last line in the buffer
        const endIndex = lastLineEndIndex(bytes);
        var remain = buffer[@min(buffer.len, endIndex + 2)..];
        while (remain.len > 0 and remain[0] == '\n') : (remain = remain[1..]) {}
        while (remain.len > 0 and remain[remain.len - 1] == '\n') : (remain.len -= 1) {}
        bytes = bytes[0 .. endIndex + 1];

        ut.debug.print("=== BUFFER\n\"{s}\"\n=== BYTES\n\"{s}\"\n=== REMAIN\n\"{s}\"\n===      \n", .{ buffer, bytes, remain });

        // Schedule a thread to parse the buffer
        try TaskContext.spawn(sharedContext, &pool, bytes, blockCount);

        // once the task is spawned i can mock about with bytes again to read more data from the file
        std.mem.copyForwards(u8, buffer, remain);
        readSize = try self.file.read(buffer[remain.len..]);
        bytes = buffer[@intFromBool(buffer[0] == '\n') .. readSize + remain.len];
    }

    sharedContext.waitGroup.wait();

    const result: BRCParseResult = (&sharedContext.result).*;
    return result;
}

pub fn read(self: *BRCParser) !BRCParseResult {
    const readFn = comptime switch (builtin.single_threaded) {
        true => read_SingleThread,
        false => read_MultiThread,
    };

    return readFn(self);
}

/// Returns the index of the last character in the last line of `bytes`
fn lastLineEndIndex(bytes: []const u8) usize {
    var i: usize = bytes.len - 1;
    if (bytes[i] == '\n') return i - 1;
    const l = @min(5, bytes.len);
    while (i > l) {
        i -= 1;
        if (bytes[i] == '\n') return i - 1;
        if (bytes[i] == '.' and bytes[i + 1] >= '0' and bytes[i + 1] <= '9') {
            return i + 1;
        }
    }

    std.log.err("Could not find lastLineEnd in:\n\"{s}\"", .{bytes});
    @panic("bytes was not properly formatted BRC!");
}
