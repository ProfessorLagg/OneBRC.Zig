const builtin = @import("builtin");
const std = @import("std");

const _asm = @import("_asm.zig");
// const LineReader = DelimReader(std.fs.File.Reader, '\n', 4096);
const LineReader = switch (builtin.os.tag) {
    .windows => @import("delimReader.zig").VirtualAllocDelimReader(std.fs.File.Reader, '\n'),
    else => @import("delimReader.zig").DelimReader(std.fs.File.Reader, '\n', 1_073_741_824),
};
const BRCBucketMap = @import("BRCBucketMap.zig").BRCBucketMap;
const BRCHashMap = @import("BRCHashMap.zig").BRCHashMap;
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

    fn init_adaptor(linecount: usize, allocator: std.mem.Allocator, comptime T: type, adaptor: fn (T) ResultEntry, items: []const T) !BRCParseResult {
        const entries: []ResultEntry = try allocator.alloc(ResultEntry, items.len);
        for (0..items.len) |i| {
            entries[i] = adaptor(items[i]);
            entries[i].key = try ut.mem.clone(u8, allocator, entries[i].key);
        }
        sortEntries(entries);

        return BRCParseResult{
            .allocator = allocator,
            .linecount = linecount,
            .entries = entries,
        };
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
        try map.addByClonePreHashed(keystr, valint, keyhash);
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
    const block_size: comptime_int = 8_388_608;
    const map_capacity: comptime_int = 131072; // Performed the best in benchmarks

    const ThreadPool = std.Thread.Pool;
    const Mutex = std.Thread.Mutex;
    const WaitGroup = std.Thread.WaitGroup;
    const HashMap = BRCHashMap(u32, ut.hashing.fnv1a32);
    const BRCBlockReader = @import("BRCBlockReader.zig").BRCBlockReader(@TypeOf(self.file), block_size);

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });

    // shared context
    const SharedContext = struct {
        const Tsctx = @This();
        allocator: std.mem.Allocator = undefined,
        linecount: usize = 0,
        linecount_lock: Mutex = .{},
        // TODO Try out using a cpu count number of HashMaps, and then using threadId / block id to find which one to lock and merge to
        maps: []HashMap = undefined,
        locks: []Mutex = undefined,
        activeTasksCount: usize = 0,

        fn init(allocator: std.mem.Allocator) !*Tsctx {
            const map_count = std.math.ceilPowerOfTwoAssert(usize, std.Thread.getCpuCount() catch 1);

            const sctx: *Tsctx = try allocator.create(Tsctx);
            sctx.* = Tsctx{};
            sctx.allocator = allocator;
            sctx.maps = try allocator.alloc(HashMap, map_count);
            sctx.locks = try allocator.alloc(Mutex, map_count);
            for (0..map_count) |i| {
                sctx.maps[i] = try HashMap.init(allocator, map_capacity);
                sctx.locks[i] = .{};
            }
            return sctx;
        }
        fn deinit(sctx: *Tsctx, deinitMaps: bool) void {
            if (deinitMaps) for (0..sctx.maps.len) |i| sctx.maps[i].deinit();

            sctx.allocator.free(sctx.maps);
            sctx.allocator.free(sctx.locks);
            sctx.allocator.destroy(sctx);
        }
    };
    // Gotta put anything that touches a thread on the heap
    const sharedContext: *SharedContext = try SharedContext.init(self.allocator); //self.allocator.create();
    defer sharedContext.deinit(false);

    const TaskContext = struct {
        const Tctx = @This();
        shared: *SharedContext,
        block: []const u8,
        blockId: usize,

        /// Processses `block` into `map`.
        /// Locks `map_lock` while working
        /// Returns the number of lines found in `block`
        fn process(ctx: *Tctx) !usize {
            const mapIdx: usize = ctx.blockId % ctx.shared.maps.len;
            const map: *HashMap = &ctx.shared.maps[mapIdx];
            const map_lock: *Mutex = &ctx.shared.locks[mapIdx];
            map_lock.lock();
            defer map_lock.unlock();
            var lineIter = std.mem.splitScalar(u8, ctx.block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| : (localCount += 1) {
                std.debug.assert(line.len >= 5);
                const splitAndHashResult = ut.hashing.fnv1a32UntilDelim(';', line);
                // if(splitAndHashResult.delim_index == null){
                //     ut.debug.printLn("block {d}, line {d}: \"{s}\" | {any}", .{ ctx.blockId, localCount, line, line });
                //     ut.debug.flush();
                // }
                std.debug.assert(splitAndHashResult.delim_index != null);

                const splitIndex: usize = splitAndHashResult.delim_index.?;
                const keyhash: u32 = splitAndHashResult.hash;
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
                try map.addByClonePreHashed(keystr, valint, keyhash);
            }
            return localCount;
        }

        fn run(ctx: *Tctx) void {
            _asm.add_direct(&ctx.shared.activeTasksCount, 1);
            defer {
                _asm.sub_direct(&ctx.shared.activeTasksCount, 1);
                ctx.deinit();
            }

            const localCount: usize = ctx.process() catch |e| b: {
                ut.debug.print("Thread error: {any}{any}", .{ e, @errorReturnTrace() });
                break :b 0;
            };

            _asm.add_direct(&ctx.shared.linecount, localCount);
        }

        fn deinit(ctx: *Tctx) void {
            ctx.shared.allocator.free(ctx.block.ptr[0..block_size]);
            ctx.shared.allocator.destroy(ctx);
        }

        /// Merges `src` into `dst` and calls `.freeKeys()` and `.deinit()` on `src`
        fn mergeFree(src: *HashMap, dst: *HashMap) void {
            var iter = src.iterator();
            while (iter.next()) |entry| dst.mergeEntryByClone(entry) catch |err| {
                ut.debug.print("{any}{any}", .{ err, @errorReturnTrace() });
                @panic("HashMap.mergeEntryByClone failed");
            };
            src.freeKeys();
            src.deinit();
        }

        fn adaptEntry(entry: HashMap.Entry) BRCParseResult.ResultEntry {
            var r: BRCParseResult.ResultEntry = undefined;
            r.key.ptr = entry.keyptr;
            r.key.len = entry.keylen;
            r.val = entry.value;
            return r;
        }
    };

    var blockReader: BRCBlockReader = BRCBlockReader.init(self.allocator, self.file);
    var blockCount: usize = 0;
    while (try blockReader.next()) |block| {
        blockCount += 1;
        // ut.debug.print("=== block {d} ===\n", .{blockCount});
        // ut.debug.print("\"{s}\"\n{any}\n", .{ block, block });
        // ut.debug.flush();
        // Schedule a thread to parse the buffer
        const ctx: *TaskContext = try sharedContext.allocator.create(TaskContext);
        ctx.shared = sharedContext;
        ctx.block = block;
        ctx.blockId = blockCount;
        try pool.spawn(TaskContext.run, .{ctx});
    }
    while (sharedContext.activeTasksCount > 0) {}

    // Merging maps into sharedContext.maps[0]
    const mapCount: usize = sharedContext.maps.len;
    std.debug.assert(mapCount != 0);
    std.debug.assert(std.math.isPowerOfTwo(mapCount));

    var round: usize = 1;
    var merge_wg: WaitGroup = .{};
    while (round < mapCount) : (round *= 2) {
        ut.debug.print("merge round {d}\n", .{round});

        var src_idx: usize = round;
        while (src_idx < mapCount) : (src_idx += round * 2) {
            const dst_idx: usize = src_idx - round;
            ut.debug.print("\t{d} <- {d}\n", .{ dst_idx, src_idx });

            const src_map: *HashMap = @constCast(&sharedContext.maps[src_idx]);
            const dst_map: *HashMap = @constCast(&sharedContext.maps[dst_idx]);
            pool.spawnWg(&merge_wg, TaskContext.mergeFree, .{ src_map, dst_map });
        }
    }
    pool.waitAndWork(&merge_wg);

    const finalMap: *HashMap = &sharedContext.maps[0];
    const final_entries = try self.allocator.alloc(HashMap.Entry, finalMap.count);
    defer {
        finalMap.freeKeys();
        finalMap.deinit();
        self.allocator.free(final_entries);
    }

    var i: usize = 0;
    var iter = finalMap.iterator();
    while (iter.next()) |entry| : (i += 1) final_entries[i] = entry.*;

    return BRCParseResult.init_adaptor(sharedContext.linecount, self.allocator, HashMap.Entry, TaskContext.adaptEntry, final_entries);
}

pub fn parse(self: *BRCParser) !BRCParseResult {
    // const parseFn = comptime switch (builtin.single_threaded) {
    //     true => parse_SingleThread,
    //     false => parse_MultiThread,
    // };
    // return parseFn(self);
    return parse_MultiThread(self);
}

fn read_SingleThread(self: *BRCParser) !BRCParseResult {
    const buffer: []u8 = try self.allocator.alignedAlloc(u8, 4096, 8_388_608);
    defer self.allocator.free(buffer);
    var readSize: usize = try self.file.read(buffer);
    while (readSize > 0) : (readSize = try self.file.read(buffer)) {}
    return BRCParseResult{ .linecount = 1 };
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

fn parse_MultiThread_PreAllocate(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const Mutex = std.Thread.Mutex;
    const WaitGroup = std.Thread.WaitGroup;
    const HashMap = BRCHashMap(u32, ut.hashing.fnv1a32);

    const block_size: comptime_int = 8_388_608;
    const map_capacity: comptime_int = 131072; // Performed the best in benchmarks

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });
    defer pool.deinit();

    // shared context
    const SharedContext = struct {
        const Tsctx = @This();
        allocator: std.mem.Allocator = undefined,
        linecount: usize = 0,
        maps: []HashMap = undefined,
        locks: []Mutex = undefined,
        waitGroup: WaitGroup = .{},

        fn init(allocator: std.mem.Allocator) !*Tsctx {
            const map_count = std.math.ceilPowerOfTwoAssert(usize, std.Thread.getCpuCount() catch 1);

            const sctx: *Tsctx = try allocator.create(Tsctx);
            sctx.allocator = allocator;
            sctx.linecount = 0;

            sctx.maps = try allocator.alloc(HashMap, map_count);
            sctx.locks = try allocator.alloc(Mutex, map_count);
            for (0..map_count) |i| {
                sctx.maps[i] = try HashMap.init(allocator, map_capacity);
                sctx.locks[i] = .{};
            }
            sctx.waitGroup = .{};
            return sctx;
        }
        fn deinit(sctx: *Tsctx, deinitMaps: bool) void {
            if (deinitMaps) for (0..sctx.maps.len) |i| sctx.maps[i].deinit();
            sctx.allocator.free(sctx.maps);
            sctx.allocator.free(sctx.locks);
            sctx.allocator.destroy(sctx);
        }
    };
    // Gotta put anything that touches a thread on the heap
    const sharedContext: *SharedContext = try SharedContext.init(self.allocator); //self.allocator.create();
    defer sharedContext.deinit(false);

    const TaskContext = struct {
        const Tctx = @This();
        shared: *SharedContext,
        block: []const u8,
        len: usize,
        blockId: usize,

        /// Processses `block` into `map`.
        /// Locks `map_lock` while working
        /// Returns the number of lines found in `block`
        fn process(block: []const u8, map: *HashMap, map_lock: *Mutex) !usize {
            map_lock.lock();
            defer map_lock.unlock();
            var lineIter = std.mem.splitScalar(u8, block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| : (localCount += 1) {
                // ut.debug.print("line {d}: \"{s}\" | {any} \n", .{ localCount, line, line });
                // ut.debug.flush();

                std.debug.assert(line.len >= 5);

                const splitAndHashResult = ut.hashing.fnv1a32UntilDelim(';', line);
                std.debug.assert(splitAndHashResult.delim_index != null);
                const splitIndex: usize = splitAndHashResult.delim_index.?;
                const keyhash: u32 = splitAndHashResult.hash;
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
                try map.addByClonePreHashed(keystr, valint, keyhash);
            }
            return localCount;
        }

        fn run(ctx: *Tctx) void {
            @setRuntimeSafety(false);
            defer @call(.always_inline, Tctx.deinit, .{ctx});
            const mapIdx: usize = ctx.blockId % ctx.shared.maps.len;
            const map: *HashMap = &ctx.shared.maps[mapIdx];
            const map_lock: *Mutex = &ctx.shared.locks[mapIdx];
            const localCount: usize = Tctx.process(ctx.block, map, map_lock) catch |e| b: {
                ut.debug.print("Thread error: {any}{any}", .{ e, @errorReturnTrace() });
                break :b 0;
            };

            _asm.sumDirect(&ctx.shared.linecount, localCount);
        }

        fn deinit(ctx: *Tctx) void {
            ctx.shared.allocator.destroy(ctx);
        }

        /// Merges `src` into `dst` and calls `.freeKeys()` and `.deinit()` on `src`
        fn mergeAndFree(src: *HashMap, dst: *HashMap) void {
            var iter = src.iterator();
            while (iter.next()) |entry| dst.mergeEntryByClone(entry) catch |err| {
                ut.debug.print("{any}{any}", .{ err, @errorReturnTrace() });
                @panic("HashMap.mergeEntryByClone failed");
            };
            src.freeKeys();
            src.deinit();
        }
    };
    const file_size = self.file.getEndPos() catch (try self.file.stat()).size;
    const buffer: []u8 = try std.heap.page_allocator.alignedAlloc(u8, std.heap.pageSize(), file_size);
    defer std.heap.page_allocator.free(buffer);

    var blockCount: usize = 0;

    var left: usize = 0;
    var right: usize = block_size;
    var rem: usize = 0;
    loop: while (true) {
        if (left >= buffer.len) break :loop;

        right = left + rem + block_size;
        const readSize: usize = try self.file.read(buffer[left + rem .. @min(right, buffer.len)]);

        blockCount += 1;

        // find end of last line
        rem = 0;
        switch (readSize) {
            0 => break :loop,
            block_size => {
                while (buffer[right] != '\n' and right > left) {
                    right -= 1;
                    rem += 1;
                }
            },
            else => right = buffer.len,
        }

        // Schedule a thread to parse the buffer
        const ctx: *TaskContext = try sharedContext.allocator.create(TaskContext);
        ctx.shared = sharedContext;
        ctx.block = buffer[left..right];
        ctx.blockId = blockCount;
        ut.debug.print("scheduling blockId{d}\n", .{ctx.blockId});
        pool.spawnWg(&sharedContext.waitGroup, TaskContext.run, .{ctx});

        // adjust pointers
        left = right;
        if (left < buffer.len and buffer[left] == '\n') {
            left += 1;
            rem -= @intFromBool(rem > 0);
        }
    }

    sharedContext.waitGroup.wait();

    // Merging maps into sharedContext.maps[0]
    const mapCount: usize = sharedContext.maps.len;
    std.debug.assert(mapCount != 0);
    std.debug.assert(std.math.isPowerOfTwo(mapCount));

    var round: usize = 1;

    while (round < mapCount) : (round *= 2) {
        ut.debug.print("merge round {d}\n", .{round});

        var merge_wg: WaitGroup = .{};
        var src_idx: usize = round;
        while (src_idx < mapCount) : (src_idx += round * 2) {
            const dst_idx: usize = src_idx - round;
            ut.debug.print("\t{d} <- {d}\n", .{ dst_idx, src_idx });

            const src_map: *HashMap = @constCast(&sharedContext.maps[src_idx]);
            const dst_map: *HashMap = @constCast(&sharedContext.maps[dst_idx]);
            pool.spawnWg(&merge_wg, TaskContext.mergeAndFree, .{ src_map, dst_map });
        }
        WaitGroup.wait(&merge_wg);
    }

    const finalMap: *HashMap = &sharedContext.maps[0];

    // collecting and sorting entries:
    const entries: []BRCParseResult.ResultEntry = try self.allocator.alloc(BRCParseResult.ResultEntry, finalMap.count);
    var iter = finalMap.iterator();
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
        .linecount = sharedContext.linecount,
    };
}

fn parse_MultiThread_MappedFile(self: *BRCParser) !BRCParseResult {
    const ThreadPool = std.Thread.Pool;
    const Mutex = std.Thread.Mutex;
    const WaitGroup = std.Thread.WaitGroup;
    const HashMap = BRCHashMap(u32, ut.hashing.fnv1a32);
    const MappedFile = @import("MappedFile.zig").MappedFile(.{ .enableWriting = false, .largePages = false });

    const block_size: comptime_int = 1024 * 64; //8_388_608;
    const map_capacity: comptime_int = 131072; // Performed the best in benchmarks

    var pool: ThreadPool = undefined;
    try pool.init(.{ .allocator = self.allocator });
    defer pool.deinit();

    // shared context
    const SharedContext = struct {
        const Tsctx = @This();
        allocator: std.mem.Allocator = undefined,
        linecount: usize = 0,
        maps: []HashMap = undefined,
        locks: []Mutex = undefined,
        waitGroup: WaitGroup = .{},

        fn init(allocator: std.mem.Allocator) !*Tsctx {
            const map_count = std.math.ceilPowerOfTwoAssert(usize, std.Thread.getCpuCount() catch 1);

            const sctx: *Tsctx = try allocator.create(Tsctx);
            sctx.allocator = allocator;
            sctx.linecount = 0;

            sctx.maps = try allocator.alloc(HashMap, map_count);
            sctx.locks = try allocator.alloc(Mutex, map_count);
            for (0..map_count) |i| {
                sctx.maps[i] = try HashMap.init(allocator, map_capacity);
                sctx.locks[i] = .{};
            }

            sctx.linecount_lock = .{};
            sctx.waitGroup = .{};
            return sctx;
        }
        fn deinit(sctx: *Tsctx, deinitMaps: bool) void {
            if (deinitMaps) for (0..sctx.maps.len) |i| sctx.maps[i].deinit();

            sctx.allocator.free(sctx.maps);
            sctx.allocator.free(sctx.locks);
            sctx.allocator.destroy(sctx);
        }
    };
    // Gotta put anything that touches a thread on the heap
    const sharedContext: *SharedContext = try SharedContext.init(self.allocator); //self.allocator.create();
    defer sharedContext.deinit(false);

    const TaskContext = struct {
        const Tctx = @This();
        shared: *SharedContext,
        taskId: usize,
        block: []const u8,
        view: MappedFile.View,

        /// Processses `block` into `map`.
        /// Locks `map_lock` while working
        /// Returns the number of lines found in `block`
        fn process(block: []const u8, map: *HashMap, map_lock: *Mutex) !usize {
            map_lock.lock();
            defer map_lock.unlock();
            var lineIter = std.mem.splitScalar(u8, block, '\n');
            var localCount: usize = 0;
            while (lineIter.next()) |line| : (localCount += 1) {
                std.debug.assert(line.len >= 5);

                const splitAndHashResult = ut.hashing.fnv1a32UntilDelim(';', line);
                std.debug.assert(splitAndHashResult.delim_index != null);
                const splitIndex: usize = splitAndHashResult.delim_index.?;
                const keyhash: u32 = splitAndHashResult.hash;
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
                try map.addByClonePreHashed(keystr, valint, keyhash);
            }
            return localCount;
        }

        fn run(ctx: *Tctx) void {
            defer ctx.deinit();
            const mapIdx: usize = ctx.taskId % ctx.shared.maps.len;
            const map: *HashMap = &ctx.shared.maps[mapIdx];
            const map_lock: *Mutex = &ctx.shared.locks[mapIdx];
            const localCount: usize = Tctx.process(ctx.block, map, map_lock) catch |e| b: {
                ut.debug.print("Thread error: {any}{any}", .{ e, @errorReturnTrace() });
                break :b 0;
            };
            _asm.sumDirect(&ctx.shared.linecount, localCount);
        }

        fn deinit(ctx: *Tctx) void {
            ctx.view.destroy();
            ctx.shared.allocator.destroy(ctx);
        }

        fn spawn(shared: *SharedContext, threadPool: *ThreadPool, id: usize, view: *const MappedFile.View, len: usize) !void {
            const ctx: *Tctx = try shared.allocator.create(Tctx);
            ctx.shared = shared;
            ctx.block = view.bytes[0..len];
            ctx.taskId = id;
            threadPool.spawnWg(&shared.waitGroup, run, .{ctx});
        }

        /// Merges `src` into `dst` and calls `.freeKeys()` and `.deinit()` on `src`
        fn mergeAndFree(src: *HashMap, dst: *HashMap) void {
            var iter = src.iterator();
            while (iter.next()) |entry| dst.mergeEntryByClone(entry) catch |err| {
                ut.debug.print("{any}{any}", .{ err, @errorReturnTrace() });
                @panic("HashMap.mergeEntryByClone failed");
            };
            src.freeKeys();
            src.deinit();
        }
    };

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try ut.fs.getFilePath(self.file, &path_buffer);
    //self.file.close(); // We dont need it to be open anymore, since it might interfere with the mapping the file
    var mappedFile: MappedFile = try MappedFile.init(path);
    defer mappedFile.deinit();
    const file_size: usize = mappedFile.getSize();

    var index: usize = 0;
    var prevIndex: isize = -1; // only here for debug
    var block_count: usize = 0;
    while (index < file_size) {
        std.debug.assert(@as(isize, @intCast(index)) > prevIndex);
        const view: MappedFile.View = try mappedFile.createView(index, block_size);
        block_count += 1;
        std.log.debug("blockCount: {d}\n", .{block_count});

        // Find end of the last line in the buffer
        const parseLen: usize = if (view.bytes.len < block_size) view.bytes.len else if (view.bytes.len == block_size) std.mem.lastIndexOfScalar(u8, view.bytes, '\n') orelse unreachable else unreachable;

        // Schedule a thread to parse the buffer
        try TaskContext.spawn(sharedContext, &pool, block_count, &view, parseLen);
        prevIndex = @intCast(index);
        index += parseLen + 1;
    }

    sharedContext.waitGroup.wait();

    // Merging maps into sharedContext.maps[0]
    const mapCount: usize = sharedContext.maps.len;
    std.debug.assert(mapCount != 0);
    std.debug.assert(std.math.isPowerOfTwo(mapCount));

    var round: usize = 1;

    while (round < mapCount) : (round *= 2) {
        ut.debug.print("merge round {d}\n", .{round});

        var merge_wg: WaitGroup = .{};
        var src_idx: usize = round;
        while (src_idx < mapCount) : (src_idx += round * 2) {
            const dst_idx: usize = src_idx - round;
            ut.debug.print("\t{d} <- {d}\n", .{ dst_idx, src_idx });

            const src_map: *HashMap = @constCast(&sharedContext.maps[src_idx]);
            const dst_map: *HashMap = @constCast(&sharedContext.maps[dst_idx]);
            pool.spawnWg(&merge_wg, TaskContext.mergeAndFree, .{ src_map, dst_map });
        }
        WaitGroup.wait(&merge_wg);
    }

    const finalMap: *HashMap = &sharedContext.maps[0];

    // collecting and sorting entries:
    const entries: []BRCParseResult.ResultEntry = try self.allocator.alloc(BRCParseResult.ResultEntry, finalMap.count);
    var iter = finalMap.iterator();
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
        .linecount = sharedContext.linecount,
    };
}
