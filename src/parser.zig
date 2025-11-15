const builtin = @import("builtin");
const std = @import("std");
const Alignment = std.mem.Alignment;
const Thread = std.Thread;
const ResetEvent = Thread.ResetEvent;
const Mutex = Thread.Mutex;
//const Mutex = lib.SpinningMutex;

const lib = @import("brc_lib");
const LineSplitter = lib.LineSplitter;
const Stat = lib.Stat;

pub const DefaultParser = Parser(1 << 16);

pub fn Parser(comptime BRCmapCapacity: comptime_int) type {
    comptime if (!builtin.cpu.arch.isX86() or @bitSizeOf(usize) != 64) @compileError(@typeName(Parser) ++ " only works on x64");

    return struct {
        const BRCMap: type = lib.BRCMap(BRCmapCapacity);
        const BRCMapUnmanaged: type = lib.BRCMapUnmanaged(BRCmapCapacity);

        fn printMap(allocator: std.mem.Allocator, map: *const BRCMapUnmanaged) !void {
            // Sort the entries
            const Entry = struct {
                const Self = @This();
                key: []const u8,
                val: *const Stat,
                pub fn compareR(a: *const Self, b: *const Self) lib.sorting.CompareResult {
                    return @call(.always_inline, lib.sorting.compareStrings, .{ a.key, b.key });
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
                if (map.keys[i].isEmpty()) continue;
                entries[entryId] = Entry{
                    .key = map.keys[i].get(),
                    .val = &map.values[i],
                };
                entryId += 1;
            }
            lib.sorting.insertionSortR(Entry, Entry.compareR, entries);

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

        pub fn parseLine(line: []const u8, out_key: *[]const u8, out_val: *i16) void {
            std.debug.assert(line.len >= 5);
            std.debug.assert(line[0] != '\n');
            std.debug.assert(line[line.len - 1] != '\n');
            const split_index: usize = b: {
                @setRuntimeSafety(false);
                const left: usize = line.len - @min(line.len, 6);
                const r: usize = (@intFromBool(line[left] == ';') * left) + (@intFromBool(line[left + 1] == ';') * (left + 1)) + (@intFromBool(line[left + 2] == ';') * (left + 2));
                break :b r;
            };
            out_key.* = line[0..split_index];
            std.debug.assert(out_key.len >= 1);
            std.debug.assert(out_key.len <= 100);
            std.debug.assert(out_key.len >= 1);

            const val_str: []const u8 = line[split_index + 1 ..];
            std.debug.assert(val_str.len >= 3);
            std.debug.assert(val_str.len <= 5);
            std.debug.assert(val_str[val_str.len - 2] == '.');
            std.debug.assert((out_key.len + val_str.len) == (line.len - 1));
            out_val.* = lib.brcIntParse(val_str);
        }

        pub fn parseBlock(map: *BRCMapUnmanaged, block: []const u8) void {
            var iter: LineSplitter = .{ .buffer = block };
            var lineId: usize = 0;
            while (iter.next()) |line| : (lineId += 1) {
                var key: []const u8 = undefined;
                var val: i16 = undefined;
                parseLine(line, &key, &val);

                map.addOrUpdate(key, val);
            }
        }

        const ThreadContext = struct {
            const Self = @This();

            arena: std.heap.ArenaAllocator,
            gpa: std.mem.Allocator,
            mappedFile: lib.MappedFile,
            fileSize: u64,
            blockSize: u64,
            blockCount: u64,
            maps: []BRCMapUnmanaged,
            blocks: [][]const u8,
            partial_lines: [][]const u8,
            thread_locks: []Mutex,

            pub fn init(self: *Self, _gpa: std.mem.Allocator, p: []const u8) void {
                self.arena = std.heap.ArenaAllocator.init(_gpa);
                self.gpa = self.arena.allocator();
                self.fileSize = getFilePathSize(p) catch |err| logAndPanic(err);
                self.mappedFile = lib.MappedFile.init(p) catch |err| logAndPanic(err);

                // Collect neccecary information
                self.blockCount = Thread.getCpuCount() catch unreachable; // This should not be possible to fail, since we're constrained to x64
                self.blockSize = nextMultipleOf(
                    u64,
                    std.math.divCeil(u64, self.fileSize, self.blockCount) catch self.fileSize / self.blockCount, // would require file_size to be close to 16 Exbibytes (2^64 bytes), which is not likely.
                    std.heap.page_size_min,
                );
                std.debug.assert((self.blockSize * self.blockCount) >= self.fileSize);

                // Allocate buffers and maps
                self.blocks = alignedAllocPanic(self.gpa, []const u8, .@"64", self.blockCount);
                self.partial_lines = alignedAllocPanic(self.gpa, []const u8, .@"64", self.blockCount * 2); // TODO Use the pointer trick to turn these from 16 bytes per partial into 8 bytes
                self.maps = allocPanic(self.gpa, BRCMapUnmanaged, self.blockCount);
                self.thread_locks = allocPanic(self.gpa, Mutex, self.blockCount);

                // Initialize everything that was just allocated
                @memset(self.blocks, std.mem.zeroes([]const u8));
                @memset(self.partial_lines, std.mem.zeroes([]const u8));
                @memset(self.thread_locks, Mutex{});
                for (0..self.blockCount) |i| self.maps[i] = BRCMapUnmanaged.init(self.gpa) catch |err| logAndPanic(err);
            }

            pub fn deinit(self: *Self) void {
                self.arena.deinit();
            }

            pub fn run(self: *Self) void {
                lib.debug.assert(self.thread_locks.len == self.blockCount);
                lib.debug.assert(self.blocks.len == self.blockCount);

                // Read Blocks and start threads
                var blockId: usize = 0;
                var iter = ChunkIterator(u8){
                    .buffer = self.mappedFile.slice[0..],
                    .size = self.blockSize,
                };
                while (iter.next()) |block| : (blockId += 1) {
                    {
                        self.thread_locks[blockId].lock();
                        defer self.thread_locks[blockId].unlock();
                        self.blocks[blockId] = block;
                    }

                    if (blockId < self.blockCount - 1) { // save 1 block for the main tread
                        @branchHint(.likely);
                        runDetached(.{ .allocator = self.gpa }, threadFn, .{ self, blockId }) catch |err| logAndPanic(err);
                    }
                }

                // Parse the last block on the main thread
                self.threadFn(self.blockCount - 1);

                // Wait for the remaining threads to finish
                const final_map: *BRCMapUnmanaged = &self.maps[self.blockCount - 1];
                for (1..self.blockCount) |I| {
                    const i = self.blockCount - 1 - I;
                    self.thread_locks[i].lock();
                    final_map.merge(&self.maps[i]);
                }

                // Combine and parse partial Lines
                self.combineAndParsePartials(final_map);

                // Print the final map
                printMap(self.gpa, final_map) catch |err| logAndPanic(err);
            }

            fn threadFn(self: *Self, blockId: usize) void {
                Mutex.lock(&self.thread_locks[blockId]);
                defer Mutex.unlock(&self.thread_locks[blockId]);

                var block: []const u8 = self.blocks[blockId][0..];
                // Find partial lines and trim the block
                const start: usize = std.mem.indexOfScalar(u8, block, '\n') orelse 0;
                const pre_partial: []const u8 = block[0 .. start + 1];
                block = block[start + 1 ..];
                //const end: usize = lib.lastIndexOfScalar3(block, '\n') orelse block.len;

                const end: usize = std.mem.lastIndexOfScalar(u8, block, '\n') orelse block.len;
                const post_partial: []const u8 = block[end..];
                block = block[0..end];

                // Write partial lines. We write both togehter to improve cache hit chance
                self.partial_lines[blockId * 2] = pre_partial;
                self.partial_lines[(blockId * 2) + 1] = post_partial;
                // Parse the block
                parseBlock(&self.maps[blockId], block);
            }

            fn combineAndParsePartials_old(self: *Self, final_map: *BRCMapUnmanaged) void {
                var line_buffer: [128]u8 = undefined;
                var line_fba = std.heap.FixedBufferAllocator.init(line_buffer[0..]);
                const fba = line_fba.allocator();
                var key: []const u8 = undefined;
                var val: i16 = undefined;

                var slices: []const []const u8 = undefined;
                slices.len = 2;
                var line: []const u8 = std.mem.trim(u8, self.partial_lines[0], "\n");
                var Pi: usize = 1;
                while (Pi < self.partial_lines.len) : (Pi += 2) {
                    parseLine(line, &key, &val);
                    final_map.addOrUpdate(key, val);

                    slices.ptr = @ptrCast(&self.partial_lines[Pi]);
                    line_fba.end_index = 0;
                    line = std.mem.concat(fba, u8, slices) catch |err| logAndPanic(err);
                    line = std.mem.trim(u8, line, "\n");
                }
                parseLine(line, &key, &val);
                final_map.addOrUpdate(key, val);
            }

            fn combineAndParsePartials(self: *Self, final_map: *BRCMapUnmanaged) void {
                var buf: [128]u8 = undefined;
                var key: []const u8 = undefined;
                var val: i16 = undefined;
                parseLine(std.mem.trim(u8, self.partial_lines[0], "\n"), &key, &val);
                final_map.addOrUpdate(key, val);
                var i: usize = 2;
                while (i < self.partial_lines.len) : (i += 2) {
                    const pre_partial: []const u8 = std.mem.trim(u8, self.partial_lines[i - 1], "\n");
                    const post_partial: []const u8 = std.mem.trim(u8, self.partial_lines[i], "\n");

                    var j: usize = 0;
                    for (pre_partial) |*b| {
                        buf[j] = b.*;
                        j += 1;
                    }
                    for (post_partial) |*b| {
                        buf[j] = b.*;
                        j += 1;
                    }
                    const line = buf[0..j];
                    parseLine(line, &key, &val);
                    final_map.addOrUpdate(key, val);
                }
            }
        };

        pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !void {
            var ctx: ThreadContext = undefined;
            ctx.init(allocator, path);
            defer ctx.deinit();
            ctx.run();
        }
    };
}

fn getFileSize(file: std.fs.File) !u64 {
    switch (builtin.os.tag) {
        .windows => {
            var high: lib.c.DWORD = 0;
            const low: lib.c.DWORD = lib.c.GetFileSize(file.handle, &high);
            switch (low) {
                lib.c.INVALID_FILE_SIZE => return std.os.windows.unexpectedError(std.os.windows.GetLastError()),
                else => {
                    const h64: u64 = @as(u64, @intCast(high)) << 32;
                    const l64: u64 = @intCast(low);
                    return h64 | l64;
                },
            }
        },
        else => return file.getEndPos() catch (try file.stat()).size,
    }
}

fn getFilePathSize(path: []const u8) !u64 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try getFileSize(file);
}

/// Returns the smallest multiple of `k` that is >= `v`.
/// Only works on unsigned integers.
/// Results that would overflow are clamped to `std.math.maxInt(T)`
fn nextMultipleOf(comptime T: type, v: T, k: T) T {
    @setRuntimeSafety(false);
    comptime {
        const Ti: std.builtin.Type = @typeInfo(T);
        if (Ti != .int or Ti.int.signedness != .unsigned) @compileError("Expected unsigned integer, but found " ++ @typeName(T));
    }
    const max_v = std.math.maxInt(T) - k; // maximum value of v that wont cause an overflow
    const vs = @min(v, max_v); // v clamped to the range [0, max_v]

    const r = vs + (k - (vs % k));
    std.debug.assert(r % k == 0);
    return r;
}

fn allocPanic(allocator: std.mem.Allocator, comptime T: type, n: usize) []T {
    return allocator.alloc(T, n) catch |err| logAndPanic(err);
}

fn alignedAllocPanic(allocator: std.mem.Allocator, comptime T: type, comptime alignment: ?Alignment, n: usize) []align(if (alignment) |a| a.toByteUnits() else @alignOf(T)) T {
    return allocator.alignedAlloc(T, alignment, n) catch |err| logAndPanic(err);
}

fn logAndPanic(err: anyerror) noreturn {
    std.log.err("{any}", .{@errorReturnTrace()});
    @panic(@errorName(err));
}

fn runDetached(config: Thread.SpawnConfig, comptime function: anytype, args: anytype) !void {
    if (builtin.single_threaded) {
        const mode: std.builtin.CallModifier = if (builtin.mode == .Debug) .never_inline else .auto;
        @call(mode, function, args);
    } else {
        (try Thread.spawn(config, function, args)).detach();
    }
}

fn ChunkIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        buffer: []const T,
        size: usize,

        pub fn next(self: *Self) ?[]const T {
            if (self.buffer.len == 0) return null;
            const len = @min(self.size, self.buffer.len);
            const rsp = self.buffer[0..len];
            self.buffer = self.buffer[len..];
            return rsp;
        }
    };
}
