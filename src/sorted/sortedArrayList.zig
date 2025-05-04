const builtin = @import("builtin");
const std = @import("std");

const compare = @import("compare.zig");
const CompareResult = compare.CompareResult;
const Comparison = compare.Comparison;
const ComparisonR = compare.ComparisonR;

pub fn SortedArrayList(comptime T: type, comptime comparison: Comparison(T)) type {
    return struct {
        const BinarySearchContext = compare.BinarySearchContext(T, comparison);
        const TSelf = @This();

        allocator: std.mem.Allocator,
        buffer: []T,
        items: []T,
        lock: std.Thread.Mutex = .{},

        fn min_capacity() usize {
            const page_size: usize = std.heap.pageSize();
            const line_size: usize = std.atomic.cache_line;
            const type_size: usize = @sizeOf(T);

            const types_per_page: usize = @max(std.math.floorPowerOfTwo(page_size / type_size), 4);
            const types_per_line: usize = std.math.floorPowerOfTwo(usize, line_size / type_size);

            return std.math.clamp(types_per_line, 2, types_per_page);
        }
        fn max_capacity() usize {
            const maxUsize: usize = comptime std.math.maxInt(usize);
            const maxUsize_u64: u64 = comptime @intCast(maxUsize);

            const page_size: usize = std.heap.pageSize();
            const type_size: usize = @sizeOf(T);

            const maxMemory_u64: usize = std.process.totalSystemMemory() catch maxUsize_u64;

            const maxMemory: usize = std.math.clamp(@as(usize, @intCast(maxMemory_u64)), page_size, maxUsize);
            return maxMemory / type_size;
        }
        pub fn initCapacity(allocator: std.mem.Allocator, initial_capacity: usize) !TSelf {
            var self: TSelf = TSelf{
                .allocator = allocator,
                .buffer = undefined,
                .items = undefined,
            };
            self.allocator = allocator;

            self.buffer = try self.allocator.alloc(T, initial_capacity);
            self.items.ptr = self.buffer.ptr;
            self.items.len = 0;
            return self;
        }
        pub fn init(allocator: std.mem.Allocator) !TSelf {
            return initCapacity(allocator, min_capacity());
        }
        pub fn deinit(self: *TSelf) void {
            self.allocator.free(self.buffer);
            self.* = undefined;
        }

        pub inline fn capacity(self: *const TSelf) usize {
            return self.buffer.len;
        }
        pub inline fn len(self: *const TSelf) usize {
            return self.items.len;
        }

        fn resize(self: *TSelf, new_capacity: usize) !void {
            const new_len: usize = std.math.clamp(new_capacity, min_capacity(), max_capacity());
            if (new_len == self.capacity()) {
                @branchHint(.cold);
                return;
            }

            if (self.allocator.resize(self.buffer, new_len)) {
                self.buffer.len = new_len;
            } else {
                const new_buffer: []T = try self.allocator.alloc(T, new_len);
                const l: usize = @min(new_len, self.buffer.len);
                @memcpy(new_buffer[0..l], self.buffer[0..l]);
                self.allocator.free(self.buffer);
                self.buffer = new_buffer[0..];
                self.items = self.buffer[0..self.items.len];
            }
        }

        /// Grows buffer if needed. Returns true if buffer size was increased
        fn increaseCapacity(self: *TSelf) bool {
            const old_capacity = self.capacity();
            if (self.len() < old_capacity) return false;

            const new_capacity = old_capacity * 2;
            resize(self.allocator, &self.buffer, new_capacity);
        }

        pub fn add(self: *TSelf, item: T) !void {
            const i: usize = BinarySearchContext.binarySearchInsert(self.items, item);
            try self.insertAt(i, item);
        }

        fn insertAt(self: *TSelf, index: usize, item: T) !void {
            std.debug.assert(index <= self.items.len);

            _ = try self.increaseCapacity();
            std.debug.assert(self.buffer.len > self.items.len);
            std.debug.assert(index < self.buffer.len);

            if (index < self.items.len) {
                @branchHint(.unpredictable);
                // shift buffer
                const src: []T = self.buffer[index..self.items.len];
                const dst: []T = self.buffer[index + 1 .. self.items.len + 1];
                std.debug.assert(src.len > 0);
                std.debug.assert(dst.len == src.len);
                var i: usize = src.len;
                while (i >= 0) : (i -= 1) dst[i] = src[i];
            }

            // insert item
            self.items.len += 1;
            self.items[index] = item;
        }

        test init {
            var sal: TSelf = try TSelf.init(std.testing.allocator);
            defer sal.deinit();
            try std.testing.expectEqual(min_capacity(), sal.buffer.len);
        }
        test initCapacity {
            const c: usize = 11;
            var sal: TSelf = try TSelf.initCapacity(std.testing.allocator, c);
            defer sal.deinit();
            try std.testing.expectEqual(c, sal.buffer.len);
        }
        test deinit {
            @setRuntimeSafety(true);
            var sal: TSelf = try TSelf.init(std.testing.allocator);
            sal.deinit();
            try std.testing.expectEqual(undefined, sal);
        }
    };
}
