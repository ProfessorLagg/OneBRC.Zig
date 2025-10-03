const builtin = @import("builtin");
const std = @import("std");
const lib = @import("brc_lib");
const BRCmapCapacity: comptime_int = 1 << 16;
const BRCMap: type = lib.BRCMap(BRCmapCapacity);
const BRCMapUnmanaged: type = lib.BRCMapUnmanaged(BRCmapCapacity);
const sso = lib.sso;
const Stat = lib.Stat;
const sorting = lib.sorting;
const LineSplitter = lib.LineSplitter;
const ResetEvent = std.Thread.ResetEvent;

// pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
//     std.log.err("{s}{any}", .{ msg, trace });
//     std.process.exit(1);
// }

// following files have at most 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000.txt";

// following files have 10 000 keys, and likely more than 1 instance of each key
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\10_000_000.txt";
// var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\100_000_000.txt";
var debugfilepath: []const u8 = "C:\\CodeProjects\\1BillionRowChallenge\\data\\NoHashtag\\1_000_000_000.txt";

const static_allocator: std.mem.Allocator = b: {
    if (builtin.is_test) break :b std.testing.allocator;
    if (!builtin.single_threaded) break :b std.heap.smp_allocator;
    if (builtin.link_libc) break :b std.heap.c_allocator;
    @compileError("Requires either single-threading to be disabled or lib-c to be linked");
};

fn parseBlockUnmanaged(map: *BRCMapUnmanaged, block: []const u8) void {
    // var iter = std.mem.splitScalar(u8, block, '\n');
    var iter: LineSplitter = .{ .buffer = block };
    while (iter.next()) |line| {
        std.debug.assert(line.len >= 5);
        std.debug.assert(line[0] != '\n');
        std.debug.assert(line[line.len - 1] != '\n');

        // TODO this turns into to jumps. I can probably use some inline asm cmov to massively improve performance
        const split_index: usize = b: {
            @setRuntimeSafety(false);
            const left: usize = line.len - @min(line.len, 6);
            const r: usize = (@intFromBool(line[left] == ';') * left) + (@intFromBool(line[left + 1] == ';') * (left + 1)) + (@intFromBool(line[left + 2] == ';') * (left + 2));
            break :b r;
        };
        const key_str: []const u8 = line[0..split_index];
        const val_str: []const u8 = line[split_index + 1 ..];
        std.debug.assert(key_str.len >= 1);
        std.debug.assert(key_str.len <= 100);
        std.debug.assert(val_str.len >= 3);
        std.debug.assert(val_str.len <= 5);

        const val: i32 = lib.brcIntParse(val_str);
        map.addOrUpdate(key_str, val);
    }
}

fn parseBlock(map: *BRCMap, block: []const u8) void {
    @call(.always_inline, parseBlockUnmanaged, .{ &map.unmanaged, block });
}

inline fn getMaxBlockCount(comptime maxBlockSize: comptime_int, fileSize: u64) u64 {
    const maxLineLen: comptime_int = 107;
    const minBlockSize: u64 = comptime maxBlockSize - maxLineLen;
    const a: u64 = @divFloor(fileSize, minBlockSize);
    const b: u64 = @intFromBool(a * minBlockSize != fileSize);
    return a + b;
}

inline fn parseFileContent(allocator: std.mem.Allocator, content: []const u8) !void {
    const blocksize: comptime_int = 1024 * 1024 * 1024;
    const BlockReader: type = lib.BlockReader(blocksize, '\n');
    const ThreadContext = struct {
        const Self = @This();
        hasData: ResetEvent,
        block: []const u8,
        map: BRCMapUnmanaged,

        fn init(self: *Self, alc: std.mem.Allocator) !void {
            self.hasData = .{};
            self.block.ptr = @ptrFromInt(@sizeOf(u8));
            self.block.len = 0;
            self.map = try BRCMapUnmanaged.init(alc);
        }
        fn initMany(alc: std.mem.Allocator, count: usize) ![]Self {
            const result: []Self = try alc.alloc(Self, count);
            for (0..result.len) |i| try result[i].init(alc);
            return result;
        }
        fn deinit(self: *Self, alc: std.mem.Allocator) void {
            self.map.deinit(alc);
        }

        fn run(self: *Self) void {
            self.hasData.wait();
            defer self.hasData.reset();
            if (self.block.len > 0) parseBlockUnmanaged(&self.map, self.block);
        }

        fn set(self: *Self, block: []const u8) void {
            self.block = block;
            self.hasData.set();
        }
        fn setCancel(self: *Self) void {
            self.block.len = 0;
            self.hasData.set();
        }
    };
    var reader: BlockReader = BlockReader.init(content); // deinit is at the end of the function
    const maxBlockCount = getMaxBlockCount(blocksize, content.len);
    const contexts: []ThreadContext = try ThreadContext.initMany(allocator, maxBlockCount);
    defer allocator.free(contexts);
    // Start the tasks
    for (contexts) |*ctx| (try std.Thread.spawn(.{}, ThreadContext.run, .{ctx})).detach();

    var id: usize = 0;
    while (reader.next()) |block| : (id += 1) {
        std.debug.assert(id < contexts.len);
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');
        contexts[id].set(block);
    }

    // cancel the remaining contexts
    while (id < contexts.len) : (id += 1) contexts[id].setCancel();

    // wait for all contexts to finish
    for (contexts) |*ctx| {
        while (ctx.hasData.isSet()) {}
    }

    // merging maps
    const finalcontext: *ThreadContext = &contexts[0];
    defer finalcontext.deinit(allocator);
    const finalmap: *BRCMapUnmanaged = &finalcontext.map;
    for (contexts[1..]) |*ctx| {
        if (ctx.block.len > 0) finalmap.merge(&ctx.map);
        ctx.deinit(allocator);
    }

    try printBrcMapUnmanaged(allocator, finalmap);
}
inline fn parseFileMapped(allocator: std.mem.Allocator, path: []const u8) !void {
    var mappedFile: lib.MappedFile = try lib.MappedFile.init(path);
    defer mappedFile.deinit();
    try parseFileContent(allocator, mappedFile.slice);
}

fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const Allocator = std.mem.Allocator;
    const ThreadPool = std.Thread.Pool;
    const WaitGroup = std.Thread.WaitGroup;
    const Mutex = lib.SpinningMutex;
    const File = std.fs.File;
    const blocksize: comptime_int = 1024 * 1024 * 8;
    const BlockReader: type = lib.BlockReader(blocksize, '\n');

    const Context = struct {
        const Self = @This();
        gpa: Allocator,

        pool: *ThreadPool = undefined,
        wait_group: WaitGroup = .{},

        file: File = undefined,
        readbuffer: []u8 = undefined,

        map: BRCMap,
        map_lock: Mutex = .{},
        pub fn init(gpa: Allocator) !Self {
            var r: Self = .{
                .gpa = gpa,
                .map = try BRCMap.init(gpa),
                .pool = try gpa.create(ThreadPool),
            };
            try r.pool.init(.{ .allocator = gpa });
            return r;
        }

        pub fn deinit(self: *Self) void {
            self.pool.deinit();
            self.file.close();
            self.gpa.free(self.readbuffer);
        }

        pub fn start(self: *Self, filePath: []const u8) !void {
            self.file = try std.fs.cwd().openFile(filePath, .{});

            const file_size: u64 = self.file.getEndPos() catch (try self.file.stat()).size;

            self.readbuffer = try self.gpa.alloc(u8, file_size);
            @memset(self.readbuffer, 0);
            self.pool.spawnWg(&self.wait_group, ThreadFn.readFile, .{self});

            while (lib._asm.load_direct_8(&self.readbuffer[0]) == 0) {} // wait for reading
            var reader = BlockReader.init(self.readbuffer);
            while (reader.next()) |block| {
                std.debug.assert(block[block.len - 1] != '\n');
                self.pool.spawnWg(&self.wait_group, ThreadFn.handleBlock, .{ self, block });
                const check_idx: usize = @min(self.readbuffer.len - 1, (@intFromPtr(block.ptr) - @intFromPtr(self.readbuffer.ptr)) + blocksize);
                const check_ptr: *const u8 = @ptrCast(&self.readbuffer[check_idx]);
                while (lib._asm.load_direct_8(check_ptr) == 0) {} // wait for reading
            }
        }

        // Thread Functions
        const ThreadFn = struct {
            fn noop(_: *Self) void {}

            fn readFile(self: *Self) void {
                const readsize: usize = self.file.readAll(self.readbuffer) catch |err| b: {
                    std.log.err("{any}{any}", .{ err, @errorReturnTrace() });
                    break :b 0;
                };
                if (readsize != self.readbuffer.len) std.log.err("read fewer bytes than buffer {d} != {d}", .{ readsize, self.readbuffer.len });
            }

            fn handleBlockErr(self: *Self, block: []const u8) !void {
                var local_map: BRCMapUnmanaged = try BRCMapUnmanaged.init(self.gpa);
                defer local_map.deinit(self.gpa);
                parseBlockUnmanaged(&local_map, block);
                self.map_lock.lock();
                defer self.map_lock.unlock();
                self.map.unmanaged.merge(&local_map);
            }
            fn handleBlock(self: *Self, block: []const u8) void {
                handleBlockErr(self, block) catch |err| std.log.err("{any}{any}\n\"{s}\"", .{ err, @errorReturnTrace(), block });
            }
        };
    };
    var ctx: Context = try Context.init(allocator);
    defer ctx.deinit();

    try ctx.start(path);
    ctx.wait_group.wait();
    try printBrcMap(&ctx.map);
}

fn printBrcMapUnmanaged(allocator: std.mem.Allocator, map: *const BRCMapUnmanaged) !void {
    // Sort the entries
    const Entry = struct {
        const Self = @This();
        key: []const u8,
        val: *const Stat,
        pub fn compareR(a: *const Self, b: *const Self) sorting.CompareResult {
            return @call(.always_inline, sorting.compareStrings, .{ a.key, b.key });
        }
        pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
            _ = try writer.write(self.key);
            try writer.print("={d:.1}/{d:.1}/{d:.1}", .{
                self.val.minF(),
                self.val.meanF(),
                self.val.maxF(),
            });
        }
    };
    const entries: []Entry = try allocator.alloc(Entry, map.count);
    defer allocator.free(entries);
    var entryId: usize = 0;
    for (0..map.keys.len) |i| {
        if (map.keys[i].empty()) continue;
        entries[entryId] = Entry{
            .key = map.keys[i].get(),
            .val = &map.values[i],
        };
        entryId += 1;
    }
    sorting.insertionSortR(Entry, Entry.compareR, entries);

    // Print the output
    var stdout_buffer: [std.math.maxInt(u16)]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch |err| std.debug.panic("{any}{any}", .{ err, @errorReturnTrace() });
    try stdout.print("{{{f}", .{entries[0]});

    for (1..(entries.len - 1)) |i| {
        if (stdout.unusedCapacityLen() < (entries[i].key.len + 15)) try stdout.flush();
        try stdout.print(", {f}", .{entries[i]});
    }
    if (stdout.unusedCapacityLen() < (entries[entries.len - 1].key.len + 15)) try stdout.flush();
    try stdout.print(", {f}}}", .{entries[entries.len - 1]});
}

fn printBrcMap(map: *const BRCMap) !void {
    try printBrcMapUnmanaged(map.allocator, &map.unmanaged);
}

fn bench(filepath: []const u8) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch unreachable;

    try stderr.print("Parsing file: {s}\n", .{filepath});
    try stderr.flush();

    const fileSize = (try (try std.fs.cwd().openFile(filepath, .{})).stat()).size;
    var timer = try std.time.Timer.start();
    try parseFile(static_allocator, filepath);
    const ns = timer.read();
    const ns_f: f64 = @floatFromInt(ns);
    const s_f: f64 = ns_f / @as(f64, @floatFromInt(std.time.ns_per_s));
    const fileSize_f: f64 = @floatFromInt(fileSize);
    const perf_f: f64 = @round(fileSize_f / s_f);
    const perf: u64 = @intFromFloat(perf_f);

    try stderr.print("\n\nparsed {Bi} in {D} at {Bi}/s\n", .{
        fileSize,
        ns,
        perf,
    });
}
pub fn main() !void {
    const args = try std.process.argsAlloc(static_allocator);
    defer std.process.argsFree(static_allocator, args);
    const filepath = if (args.len == 2) args[1] else debugfilepath;
    try bench(filepath);
    //try benchmarkReading(8 * 1024 * 1024, filepath);
    //try parseFile_old(static_allocator, filepath);
    //try debug();
    //try debug_hash();
    //try benchmarkLineSplitter();
    // try benchmarkParsing(filepath);
    // try debugProgressiveBlockReader(filepath);
    _ = &filepath;
}

fn debug() !void {
    const xormask: u32 = comptime b: {
        var r: u32 = 0;
        const rb: *[4]u8 = std.mem.asBytes(&r);
        @memset(rb[0..], ';');
        break :b r;
    };

    std.debug.print("xormask: 0x{x:0>16}", .{xormask});
}
fn debug_hash() !void {
    const List = std.ArrayList([]const u8);
    const allocator: std.mem.Allocator = static_allocator;

    const capacity: comptime_int = comptime 1 << 17;
    // const capacity: comptime_int = comptime 1024 * 1024;
    const count: comptime_int = 10_000;

    const rawCities = @embedFile("cities.txt");
    const cities: [][]const u8 = try lib.splitScalarToArray(u8, rawCities, '\n', allocator);
    defer allocator.free(cities);

    // var prng = std.Random.DefaultPrng.init(@truncate(@abs(std.time.nanoTimestamp())));
    var prng = std.Random.DefaultPrng.init(2025_09_01);
    const rand = prng.random();
    rand.shuffle([]const u8, cities);

    var keys: [][]const u8 = try static_allocator.alloc([]const u8, capacity);
    defer static_allocator.free(keys);
    for (0..capacity) |i| keys[i].len = 0;

    const Context = struct {
        fn getKeyHash(key: []const u8) u64 {
            return std.hash.XxHash3.hash(0, key);
        }

        fn getBaseIndex(key: []const u8) usize {
            const hash: usize = getKeyHash(key);
            //return hash & comptime (capacity - 1);
            return hash % capacity;
        }

        fn findKeyIndex_linear(ks: [][]const u8, k: []const u8, collision_counter: *usize) usize {
            const base_index: usize = getBaseIndex(k);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset) % capacity;
                if (ks[index].len == 0) return index;
                collision_counter.* += 1;
            }
            unreachable;
        }

        fn findKeyIndex_quadratic(ks: *[capacity][]const u8, k: []const u8, collision_counter: *usize) usize {
            const base_index: usize = getBaseIndex(k);
            for (0..capacity) |offset| {
                const index: usize = (base_index + offset + offset * offset) % capacity;
                if (ks[index].len == 0) return index;
                collision_counter.* += 1;
            }
            unreachable;
        }

        fn listLessThan(_: @TypeOf(.{}), a: List, b: List) bool {
            return a.items.len > b.items.len;
        }
    };

    var collisionCount: usize = 0;
    for (cities[0..count]) |city| {
        keys[Context.findKeyIndex_linear(keys, city, &collisionCount)] = city;
    }

    const stderr = std.io.getStdErr().writer();
    const collisionRate: f64 = (@as(f64, @floatFromInt(collisionCount)) / @as(f64, @floatFromInt(count))) * 100.0;
    const loadFactor: f64 = @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(capacity)) * 100.0;
    try std.fmt.format(stderr, "collisions: {d} / {d} ({d:.2}%) | LF: {d} / {d} = {d:.2}%", .{
        collisionCount,
        count,
        @round(collisionRate * 100.0) / 100.0,
        count,
        capacity,
        @round(loadFactor * 100.0) / 100.0,
    });
}

fn debugProgressiveBlockReader(filepath: []const u8) !void {
    const readsize: comptime_int = comptime 8 * 1024 * 1024;
    const blocksize: comptime_int = comptime 1024 * 1024 * 1024;
    const BlockReader = lib.BlockReader(blocksize, '\n');
    const Alignment = std.mem.Alignment;

    const ReaderContext = struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        file: std.fs.File,
        buffer: []align(4096) u8,
        progress: usize,

        pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
            const file = try std.fs.cwd().openFile(path, .{});
            const fileSize: u64 = file.getEndPos() catch (try file.stat()).size;
            const buffer: []align(4096) u8 = try allocator.alignedAlloc(u8, Alignment.fromByteUnits(4096), fileSize);
            // @memset(buffer, 0);
            if (builtin.mode == .Debug) {
                std.debug.print("Asserting that buffer is zeroed\n", .{});
                for (buffer) |byte| if (byte != 0) return error.NotZeroed;
            }
            return Self{
                .allocator = allocator,
                .file = file,
                .buffer = buffer[0..],
                .progress = 0,
            };
        }
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.file.close();
        }

        pub fn read(self: *Self) !void {
            const start = std.time.nanoTimestamp();
            std.debug.print("begun reading {0Bi:.3} ({0d} bytes)\n", .{self.buffer.len});
            while (self.progress < self.buffer.len) {
                const left = self.progress;
                const right = @min(left + readsize, self.buffer.len);
                const buf: []u8 = self.buffer[left..right];
                _ = try self.file.read(buf);
                lib._asm.lfence();
                self.progress = right;
                lib._asm.sfence();
            }
            const end = std.time.nanoTimestamp();
            const dur: u64 = @truncate(@abs(start - end));
            const bytes_f: f64 = @floatFromInt(self.buffer.len);
            const s_f: f64 = @as(f64, @floatFromInt(dur)) / @as(f64, std.time.ns_per_s);
            const bytes_per_sec_f: f64 = bytes_f / s_f;
            const bytes_per_sec: u64 = @intFromFloat(@round(bytes_per_sec_f));
            std.debug.print("finished reading {0Bi:.3} ({0d} bytes) in {1D} | {2Bi:.3}/s\n", .{ self.buffer.len, dur, bytes_per_sec });
        }

        pub fn run(self: *Self) void {
            self.read() catch |err| std.debug.panic("{any}{any}", .{ err, @errorReturnTrace() });
        }
    };
    const BlockIterator = struct {
        const Self = @This();
        progress: *usize,
        reader: BlockReader,

        pub fn init(buffer: []const u8, progress: *usize) Self {
            return Self{
                .progress = progress,
                .reader = BlockReader.init(buffer),
            };
        }

        pub fn next_old(self: *Self) ?[]const u8 {
            const min_right = @min(self.reader.left + blocksize, self.reader.buffer.len);
            var cur_right: usize = @atomicLoad(usize, self.progress, .acquire);
            while (cur_right < min_right) : (cur_right = @atomicLoad(usize, self.progress, .acquire)) std.Thread.yield() catch continue;
            return self.reader.next();
        }

        inline fn ensureRead(self: *const Self) void {
            const testIdx: usize = @min(self.reader.left + blocksize, self.reader.buffer.len - 1);
            const testPtr: *const u8 = &self.reader.buffer[testIdx];
            var testVal: u8 = 0;
            while (testVal == 0) {
                lib._asm.sfence();
                testVal = lib._asm.load_direct_8(testPtr);
            }
        }
        pub fn next(self: *Self) ?[]const u8 {
            self.ensureRead();
            return self.reader.next();
        }
    };

    var reader: ReaderContext = try ReaderContext.init(std.heap.page_allocator, filepath);
    defer reader.deinit();
    const readThread = try std.Thread.spawn(.{}, ReaderContext.run, .{&reader});
    defer readThread.join();
    var iter: BlockIterator = BlockIterator.init(reader.buffer[0..], &reader.progress);
    var blockId: usize = 0;

    const buffer_ptr_int: usize = @intFromPtr(reader.buffer.ptr);
    const start = std.time.nanoTimestamp();
    while (iter.next()) |block| : (blockId += 1) {
        std.debug.assert(block.len <= blocksize);
        std.debug.assert(block[0] != '\n');
        std.debug.assert(block[block.len - 1] != '\n');

        std.log.debug("handling block{d}", .{blockId});
        const left_ptr_int: usize = std.mem.Alignment.forward(Alignment.fromByteUnits(4096), @intFromPtr(&block[0]));
        const right_ptr_int: usize = std.mem.Alignment.backward(Alignment.fromByteUnits(4096), @intFromPtr(&block[block.len - 1]));
        const left = left_ptr_int - buffer_ptr_int;
        const right = @min(right_ptr_int - buffer_ptr_int + 1, reader.buffer.len);

        if (left_ptr_int > buffer_ptr_int) {
            reader.allocator.free(reader.buffer[left..right]);
            std.log.debug("freed block{d}", .{blockId});
        }
    }
    const end = std.time.nanoTimestamp();
    const dur: u64 = @truncate(@abs(start - end));
    const bytes: u64 = reader.buffer.len;
    const bytes_f: f64 = @floatFromInt(bytes);
    const s_f: f64 = @as(f64, @floatFromInt(dur)) / @as(f64, std.time.ns_per_s);
    const bytes_per_sec_f: f64 = bytes_f / s_f;
    const bytes_per_sec: u64 = @intFromFloat(@round(bytes_per_sec_f));
    std.debug.print("finished reading, splitting and freeing blocks {0Bi:.3} ({0d} bytes) in {1D} | {2Bi:.3}/s\n", .{ bytes, dur, bytes_per_sec });
}

fn benchmarkLineSplitter() !void {
    const allocator: std.mem.Allocator = static_allocator;

    const Context = struct {
        const Self = @This();
        const cities = @embedFile("cities.txt");
        splitter: lib.LineSplitter,

        pub fn run(_: void) void {
            var splitter: lib.LineSplitter = .{ .buffer = cities[0..] };
            while (splitter.next()) |line| {
                _ = &line;
            }
        }
    };

    var result = lib.benchmarking.runBenchmark(void, .{
        .batchSize = 1,
        .minBatches = 1,
        .minNs = 600 * std.time.ns_per_s,
    }, Context.run, allocator, void{});
    defer result.deinit(allocator);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{f}", .{result});
    try stdout.flush();
}

fn benchmarkReadingMany(filepath: []const u8) !void {
    const maxSize: comptime_int = 1024 * 1024 * 1024;
    var size: usize = 4096;
    while (size <= maxSize) : (size *= 2) try benchmarkReading(size, filepath);
}

fn benchmarkReading(blockSize: usize, filepath: []const u8) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("benchmarkReading({Bi:>6}, \"{s}\")", .{ blockSize, filepath });
    try stdout.flush();

    const Context = struct {
        const Self = @This();
        file: std.fs.File,
        block: []u8,
        pub fn init(path: []const u8, size: usize) !Self {
            return Self{
                .file = try std.fs.cwd().openFile(path, .{ .mode = .read_only, .lock = .exclusive }),
                .block = try std.heap.page_allocator.alloc(u8, size),
            };
        }
        pub fn deinit(self: *Self) void {
            self.file.close();
            std.heap.page_allocator.free(self.block);
        }

        pub fn run(self: Self) void {
            self.file.seekTo(0) catch unreachable;
            while ((self.file.read(self.block) catch unreachable) > 0) {}
        }
    };

    var ctx: Context = try Context.init(filepath, blockSize);
    defer ctx.deinit();
    const result = lib.benchmarking.runBenchmark(Context, .{}, Context.run, static_allocator, ctx);

    try stdout.print("\rbenchmarkReading({Bi:>6}, \"{s}\"): {f}\n", .{ blockSize, filepath, result });
    try stdout.flush();
}

fn benchmarkParsing(path: []const u8) !void {
    const allocator: std.mem.Allocator = static_allocator;
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const Context = struct {
        const Self = @This();
        content: []const u8,

        pub fn run(self: Self) void {
            parseFileContent(static_allocator, self.content) catch |err| {
                std.log.err("{any}{any}", .{ err, @errorReturnTrace() });
            };
        }
    };

    const content: []u8 = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(content);
    const readSize = try file.readAll(content[0..]);
    std.debug.assert(readSize <= content.len);
    const ctx: Context = .{ .content = content[0..readSize] };

    const result = lib.benchmarking.runBenchmark(
        Context,
        .{ .batchSize = 1, .minBatches = 1, .minNs = 15 * std.time.s_per_min * std.time.ns_per_s },
        Context.run,
        allocator,
        ctx,
    );

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;
    try stderr.print("\rbenchmarkReading(\"{s}\"): {f}\n", .{ path, result });
    try stderr.flush();
}
