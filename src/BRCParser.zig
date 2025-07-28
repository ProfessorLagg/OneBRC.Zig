const builtin = @import("builtin");
const std = @import("std");

// const LineReader = DelimReader(std.fs.File.Reader, '\n', 4096);
const LineReader = switch (builtin.os.tag) {
    .windows => @import("delimReader.zig").VirtualAllocDelimReader(std.fs.File.Reader, '\n'),
    else => @import("delimReader.zig").DelimReader(std.fs.File.Reader, '\n', 1_073_741_824),
};
const BRCBucketMap = @import("BRCBucketMap.zig").BRCBucketMap;
const BRCVecstrSortedMap = @import("BRCVecstrSortedMap.zig");
const MapVal = @import("BRCMapVal.zig");
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
        while (i < entries.len) : (i += 1) {
            const x: ResultEntry = entries[i];
            var j: usize = i;
            while (j > 0 and (ResultEntry.compare_order(&entries[j - 1], &x)) == .gt) : (j -= 1) {
                entries[j] = entries[j - 1];
            }
            entries[j] = x;
        }
    }

    fn init(linecount: usize, map: *const BRCVecstrSortedMap) !BRCParseResult {
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

fn parse_SingleThread(self: *BRCParser) !BRCParseResult {
    const MapCtx = struct {
        pub fn hash(ctx: @This(), K: []const u8) u32 {
            _ = &ctx;
            return ut.hashing.fnv1a32(K);
        }

        pub fn eql(ctx: @This(), a: []const u8, b: []const u8) bool {
            _ = &ctx;
            return std.mem.eql(u8, a, b);
        }
    };
    const HashMap: type = std.HashMap([]const u8, MapVal, MapCtx, 20);

    var map: HashMap = HashMap.init(self.allocator);
    defer map.deinit();
    try map.ensureTotalCapacity(10_000);

    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var linecount: usize = 0;
    while (try lineReader.next()) |line| : (linecount += 1) {
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
        const entry = map.getOrPutAssumeCapacity(keystr);
        if (!entry.found_existing) {
            entry.key_ptr.* = try ut.mem.clone(u8, self.allocator, keystr);
            entry.value_ptr.* = MapVal.None;
        }
        MapVal.add(entry.value_ptr, valint);
    }

    // const entries:
    const entries: []BRCParseResult.ResultEntry = try self.allocator.alloc(BRCParseResult.ResultEntry, map.count());
    var iter = map.iterator();
    var i: usize = 0;
    while (iter.next()) |e| : (i += 1) {
        entries[i].val = e.value_ptr.*;
        entries[i].key = e.key_ptr.*;
    }
    BRCParseResult.sortEntries(entries);
    return BRCParseResult{
        .allocator = self.allocator,
        .entries = entries,
        .linecount = linecount,
    };
}

fn parse_SingleThread_BRCHashMap_fnv1a32(self: *BRCParser) !BRCParseResult {
    const BRCHashMap = @import("BRCHashMap.zig").BRCHashMap;
    const HashMap = BRCHashMap(u32, ut.hashing.fnv1a32);

    const map_capacity: comptime_int = 131072; // Performed the best in benchmarks
    var map: HashMap = try HashMap.init(self.allocator, map_capacity);
    defer {
        const collisionPercent = map.getCollisionPercent();
        ut.debug.print("{d:.2}% of insertions collided out of {d} keys when using a capacity of {d}", .{ collisionPercent, map.count, map.entries.len });
        map.deinit();
    }

    const fileReader = self.file.reader();
    var lineReader: LineReader = try LineReader.init(self.allocator, fileReader);
    var linecount: usize = 0;
    while (try lineReader.next()) |line| : (linecount += 1) {
        std.debug.assert(line.len >= 5);

        const splitAndHashResult = ut.hashing.fnv1a32UntilDelim(';', line);
        std.debug.assert(splitAndHashResult.delim_index != null);
        const splitIndex: usize = splitAndHashResult.delim_index.?;
        const keyhash: u32 = splitAndHashResult.hash;
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
        try map.addClonePreHashed(keystr, valint, keyhash);
    }

    // const entries:
    const entries: []BRCParseResult.ResultEntry = try self.allocator.alloc(BRCParseResult.ResultEntry, map.count);
    var iter = map.iterator();
    var i: usize = 0;
    while (iter.next()) |e| : (i += 1) {
        entries[i].val = e.value;
        entries[i].key.ptr = e.keyptr;
        entries[i].key.len = e.keylen;
    }
    BRCParseResult.sortEntries(entries);
    return BRCParseResult{
        .allocator = self.allocator,
        .entries = entries,
        .linecount = linecount,
    };
}

fn parse_MultiThread(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = std.Thread.Mutex;
    const ArenaAllocator = std.heap.ArenaAllocator;
    const bucket_count: comptime_int = 512;
    const BucketMap = BRCBucketMap(bucket_count);

    const buffer: []u8 = try self.allocator.alignedAlloc(u8, 4096, 1024 * 1024 * 2);
    defer self.allocator.free(buffer);

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });
    defer pool.deinit();

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

    const finalMap: BRCVecstrSortedMap = try sharedContext.map.finalize(self.allocator);
    return BRCParseResult.init(sharedContext.linecount, &finalMap);
}

fn parse_MultiThread_LargePageBuffer(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = std.Thread.Mutex;
    const ArenaAllocator = std.heap.ArenaAllocator;
    const bucket_count: comptime_int = 512;
    const BucketMap = BRCBucketMap(bucket_count);
    const VirtualAlloc = @import("VirtualAlloc.zig");

    const buffer: []u8 = try VirtualAlloc.allocLargePage();
    defer VirtualAlloc.freeLargePage(buffer) catch @panic("could not free large page");

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });
    defer pool.deinit();

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

    const finalMap: BRCVecstrSortedMap = try sharedContext.map.finalize(self.allocator);
    return BRCParseResult.init(sharedContext.linecount, &finalMap);
}

fn parse_MultiThread_fnva132(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = std.Thread.Mutex;
    const MapCtx = struct {
        pub fn hash(ctx: @This(), K: []const u8) u32 {
            _ = &ctx;
            return ut.hashing.fnv1a32(K);
        }

        pub fn eql(ctx: @This(), a: []const u8, b: []const u8) bool {
            _ = &ctx;
            return std.mem.eql(u8, a, b);
        }
    };
    const HashMap: type = std.HashMap([]const u8, MapVal, MapCtx, 20);

    const buffer: []u8 = try self.allocator.alignedAlloc(u8, 4096, 1024 * 1024 * 2);
    defer self.allocator.free(buffer);

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });
    defer pool.deinit();

    // shared context
    const SharedContext = struct {
        const Tsctx = @This();
        allocator: std.mem.Allocator = undefined,
        linecount: usize = 0,
        // TODO Try out using a cpu count number of HashMaps, and then using threadId / block id to find which one to lock and merge to
        map: HashMap = undefined,
        merge_lock: Mutex = .{},
        waitGroup: WaitGroup = .{},

        fn init(allocator: std.mem.Allocator) !*Tsctx {
            const r: *Tsctx = try allocator.create(Tsctx);
            r.*.allocator = allocator;
            r.*.linecount = 0;
            r.*.map = HashMap.init(allocator);
            try r.*.map.ensureTotalCapacity(10_000);

            r.*.merge_lock = .{};
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
        map: HashMap,
        block: []const u8,
        blockId: usize,

        fn run(ctx: *Tctx) void {
            defer ctx.deinit();
            var lineIter = std.mem.splitScalar(u8, ctx.block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| : (localCount += 1) {
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

                const valint: i64 = ut.math.fastIntParse(i64, valstr);
                const entry = ctx.map.getOrPutAssumeCapacity(keystr);
                if (!entry.found_existing) {
                    entry.key_ptr.* = keystr;
                    entry.value_ptr.count = 1;
                    entry.value_ptr.sum = @intCast(valint);
                    entry.value_ptr.min = @intCast(valint);
                    entry.value_ptr.max = @intCast(valint);
                } else {
                    MapVal.add(entry.value_ptr, valint);
                }
            }

            ctx.shared.merge_lock.lock();
            ut.debug.print("Merging {d} entries:\n", .{ctx.map.count()});
            var iter = ctx.map.iterator();
            while (iter.next()) |src| {
                const keystr: []const u8 = src.key_ptr.*;
                const dst = ctx.map.getOrPutAssumeCapacity(keystr);
                if (!dst.found_existing) {
                    ut.debug.print("[NEW]{s:<100} = sum:{d}, count:{d}, min:{d}, max:{d}\n", .{
                        src.key_ptr.*,
                        src.value_ptr.sum,
                        src.value_ptr.count,
                        src.value_ptr.min,
                        src.value_ptr.max,
                    });
                    dst.key_ptr.* = ut.mem.clone(u8, ctx.shared.allocator, keystr) catch |e| {
                        ut.debug.print("{any}{any}", .{ e, @errorReturnTrace() });
                        @panic("cloning keystr failed");
                    };
                    dst.value_ptr.* = src.value_ptr.*;
                } else {
                    ut.debug.print("[OLD]{s:<100} = sum:{d}, count:{d}, min:{d}, max:{d}\n", .{
                        src.key_ptr.*,
                        src.value_ptr.sum,
                        src.value_ptr.count,
                        src.value_ptr.min,
                        src.value_ptr.max,
                    });
                    MapVal.merge(dst.value_ptr, src.value_ptr);
                }
            }
            ctx.shared.linecount += localCount;
            ut.debug.flush();
            ctx.shared.merge_lock.unlock();
        }

        fn deinit(ctx: *Tctx) void {
            ctx.shared.allocator.free(ctx.block);
            ctx.map.deinit();
            ctx.shared.allocator.destroy(ctx);
        }

        fn spawn(shared: *SharedContext, threadPool: *ThreadPool, rawBytes: []const u8, id: usize) !void {
            const ctx: *Tctx = try shared.allocator.create(Tctx);
            ctx.*.shared = shared;
            ctx.*.map = HashMap.init(shared.allocator);
            try ctx.*.map.ensureTotalCapacity(10_000);
            ctx.*.block = try ut.mem.clone(u8, shared.allocator, rawBytes);
            ctx.blockId = id;
            threadPool.spawnWg(&shared.waitGroup, run, .{ctx});
        }
    };

    var readSize: usize = try self.file.read(buffer);
    var bytes: []const u8 = buffer[0..readSize];
    var blockCount: usize = 0;
    while (readSize > 0) {
        blockCount += 1;
        ut.debug.print("blockCount: {d}\n", .{blockCount});

        // Find end of the last line in the buffer
        const endIndex = lastLineEndIndex(bytes);
        var remain = buffer[@min(buffer.len, endIndex + 2)..];
        while (remain.len > 0 and remain[0] == '\n') : (remain = remain[1..]) {}
        while (remain.len > 0 and remain[remain.len - 1] == '\n') : (remain.len -= 1) {}
        bytes = bytes[0 .. endIndex + 1];

        // Schedule a thread to parse the buffer
        try TaskContext.spawn(sharedContext, &pool, bytes, blockCount);

        // once the task is spawned i can mock about with bytes again to read more data from the file
        std.mem.copyForwards(u8, buffer, remain);
        readSize = try self.file.read(buffer[remain.len..]);
        bytes = buffer[@intFromBool(buffer[0] == '\n') .. readSize + remain.len];
    }

    sharedContext.waitGroup.wait();

    ut.debug.print("keycount: {d}", .{sharedContext.map.count()});
    const entries: []BRCParseResult.ResultEntry = try self.allocator.alloc(BRCParseResult.ResultEntry, sharedContext.map.count());
    var iter = sharedContext.map.iterator();
    var i: usize = 0;
    while (iter.next()) |e| : (i += 1) {
        ut.debug.print("entry {d} | {s} = {any}", .{ i, e.key_ptr, e.value_ptr });
        entries[i].val = e.value_ptr.*;
        entries[i].key = e.key_ptr.*;
    }
    BRCParseResult.sortEntries(entries);
    return BRCParseResult{
        .allocator = self.allocator,
        .entries = entries,
        .linecount = sharedContext.linecount,
    };
}

pub fn parse(self: *BRCParser) !BRCParseResult {
    const parseFn = comptime switch (builtin.single_threaded) {
        // true => parse_SingleThread,
        true => parse_SingleThread_BRCHashMap_fnv1a32,
        //false => switch (builtin.os.tag) {
        //    .windows => parse_MultiThread_LargePageBuffer,
        //    else => parse_MultiThread,
        //},
        false => parse_MultiThread_fnva132,
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
