const builtin = @import("builtin");
const std = @import("std");
const compare = @import("compare.zig");

fn calc_default_initial_capacity(comptime Tkey: type, comptime Tval: type) comptime_int {
    const size_cacheline: comptime_int = std.atomic.cache_line;
    const size_halfcacheline: comptime_int = size_cacheline / 2;
    const size_key: comptime_int = @sizeOf(Tkey);
    const size_val: comptime_int = @sizeOf(Tval);
    const size_max = @max(size_key, size_val);
    switch (compare.compareNumber(size_max, size_halfcacheline)) {
        .Equal, .LessThan => {
            return (size_halfcacheline / size_max);
        },
        .GreaterThan => {
            return 1;
        },
    }
}

inline fn divCiel(comptime T: type, numerator: T, denominator: T) T {
    return 1 + ((numerator - 1) / denominator);
}

pub fn SortedArrayMap(comptime Tkey: type, comptime Tval: type, comptime comparison: compare.ComparisonR(Tkey)) type {
    const default_initial_capacity: comptime_int = comptime calc_default_initial_capacity(Tkey, Tval);
    return struct {
        allocator: std.mem.Allocator,
        /// The actual amount of items. Do NOT modify
        count: usize,
        /// Backing array for keys slice. Do NOT modify
        key_buffer: []Tkey,
        /// Backing array for values slice. Do NOT modify
        val_buffer: []Tval,
        keys: []Tkey,
        values: []Tval,
        const TSelf = @This();

        // === ITERATOR ===
        const BinarySearchResult: type = struct {
            index: usize,
            compare: compare.CompareResult,
        };

        // === PUBLIC ===
        pub fn init(allocator: std.mem.Allocator) !TSelf {
            const result: TSelf = try initWithCapacity(allocator, default_initial_capacity);
            return result;
        }
        pub fn initWithCapacity(allocator: std.mem.Allocator, initial_capacity: usize) !TSelf {
            std.debug.assert(initial_capacity > 0);
            var r = SortedArrayMap(Tkey, Tval, comparison){
                .allocator = allocator,
                .count = 0,
                .key_buffer = try allocator.alloc(Tkey, initial_capacity),
                .val_buffer = try allocator.alloc(Tval, initial_capacity),
                .values = undefined,
                .keys = undefined,
            };
            r.keys = r.key_buffer[0..];
            r.keys.len = 0;
            r.values = r.val_buffer[0..];
            r.values.len = 0;
            return r;
        }
        pub fn deinit(self: *TSelf) void {
            self.allocator.free(self.key_buffer);
            self.allocator.free(self.val_buffer);
        }
        /// Returns the number of values that can be contained before the backing arrays will be resized
        pub inline fn capacity(self: *TSelf) usize {
            std.debug.assert(self.key_buffer.len == self.val_buffer.len);
            return self.key_buffer.len;
        }
        /// Finds the index of the key. Returns -1 if not found
        pub inline fn indexOf(self: *TSelf, target: *const Tkey) ?usize {
            var L: isize = 0;
            var R: isize = @as(isize, @bitCast(self.count)) - @as(isize, 1);
            while (L <= R) {
                const mi: isize = @divFloor(L + R, 2);
                const mu: usize = @as(usize, @intCast(mi));
                const c = comparison(&self.keys[mu], target);
                switch (c) {
                    .LessThan => L = mi + 1,
                    .GreaterThan => R = mi - 1,
                    .Equal => return mu,
                }
            }
            return null;
        }
        /// returns the final non-null comparison
        pub inline fn search(self: *const TSelf, target: *const Tkey) BinarySearchResult {
            var L: isize = 0;
            var R: isize = @as(isize, @bitCast(self.count)) - @as(isize, 1);
            var mi: isize = @divFloor(L + R, 2);
            var mu: usize = @as(usize, @intCast(mi));
            var c: compare.CompareResult = comparison(&self.keys[mu], target);
            cmploop: while (L <= R) {
                switch (c) {
                    .LessThan => L = mi + 1,
                    .GreaterThan => R = mi - 1,
                    .Equal => break :cmploop,
                }
                mi = @divFloor(L + R, 2);
                mu = @intCast(std.math.clamp(mi, 0, @as(isize, @bitCast(self.count))));
                c = comparison(&self.keys[mu], target);
            }
            return .{ .index = mu, .compare = c };
        }
        /// Returns true if k is found in self.keys. Otherwise false
        pub inline fn contains(self: *TSelf, k: *const Tkey) bool {
            return self.indexOf(k) != null;
        }
        /// Adds an item to the set.
        /// Returns true if the key could be added, otherwise false.
        pub fn add(self: *TSelf, k: *const Tkey, v: *const Tval) bool {
            const idx = self.indexOf(k) orelse {
                self.addClobber(k, v);
                return true;
            };
            std.debug.assert(idx < self.count);
            return false;
        }
        /// Overwrites the value at k, regardless of it's already contained
        pub fn addClobber(self: *TSelf, k: *const Tkey, v: *const Tval) void {
            const insert = self.getInsertOrRealIndex(k);
            self.insertAt(insert.index, k, v);
        }

        pub const UpdateFn: type = fn (update: *Tval, v: *const Tval) void;

        /// Adds a value to the set if it is not found.
        /// Otherwise uses updateFn to update the value
        pub fn addOrUpdate(self: *TSelf, k: *const Tkey, v: *const Tval, comptime updateFn: UpdateFn) void {
            if (self.keys.len <= 0) {
                self.insertAt(0, k, v);
            }

            const idx: ?usize = self.indexOf(k);
            if (idx != null) {
                updateFn(&self.values[idx.?], v);
            } else {
                self.insertAt(self.getInsertIndex(k), k, v);
            }
        }

        /// Reduces capacity to exactly fit count
        pub fn shrinkToFit(self: *TSelf) !void {
            // TODO shrinkToFit
            _ = &self;
        }

        // === PRIVATE ===
        /// Rezises capacity to newsize
        fn resize(self: *TSelf, new_capacity: usize) void {
            std.debug.assert(new_capacity > 1);

            if (!self.allocator.resize(self.key_buffer, new_capacity)) {
                self.key_buffer = self.allocator.realloc(self.key_buffer, new_capacity) catch {
                    @panic("could not resize");
                };
                self.keys = self.key_buffer[0..self.count];
            }

            if (!self.allocator.resize(self.val_buffer, new_capacity)) {
                self.val_buffer = self.allocator.realloc(self.val_buffer, new_capacity) catch {
                    @panic("could not resize");
                };
                self.values = self.val_buffer[0..self.count];
            }
        }
        inline fn incrementCount(self: *TSelf) void {
            std.debug.assert(self.count < self.key_buffer.len);
            std.debug.assert(self.count < self.val_buffer.len);
            self.count += 1;
            self.keys = self.key_buffer[0..self.count];
            self.values = self.val_buffer[0..self.count];
            std.debug.assert(self.keys.len == self.count);
            std.debug.assert(self.values.len == self.count);
        }
        fn shiftRight(self: *TSelf, start_at: usize) void {
            std.debug.assert(start_at >= 0);
            std.debug.assert(start_at < self.count);
            std.debug.assert(self.count - start_at >= 1);
            var key_slice: []Tkey = self.keys[start_at..];
            var val_slice: []Tval = self.values[start_at..];
            var i: usize = key_slice.len;
            while (i > 1) {
                i -= 1;
                key_slice[i] = key_slice[i - 1];
                val_slice[i] = val_slice[i - 1];
            }
        }
        /// The ONLY function that's allowed to update values in the buffers!
        /// Caller asserts that the buffers have space.
        /// Caller asserts that the index is valid.
        /// Inserts an item and a key at the specified index.
        fn insertAt(self: *TSelf, index: usize, k: *const Tkey, v: *const Tval) void {
            std.debug.assert(index <= self.count); // Does not get compiled in ReleaseFast and ReleaseSmall modes

            if (self.count == self.key_buffer.len) {
                const new_capacity: usize = self.capacity() * 2;
                self.resize(new_capacity);
            }
            self.incrementCount();
            if (index == self.count - 1) {
                // No need to shift if inserting at the end
                self.keys[index] = k.*;
                self.values[index] = v.*;
                return;
            } else {
                self.shiftRight(index);
                self.keys[index] = k.*;
                self.values[index] = v.*;
            }
        }
        const ResultInsertOrRealIndex = struct { found: bool, index: usize };
        inline fn getInsertOrRealIndex(self: *TSelf, k: *const Tkey) ResultInsertOrRealIndex {
            if (self.count == 0) {
                return .{
                    .found = false,
                    .index = 0,
                };
            }

            // TODO make this use binary search!
            for (0..self.count) |i| {
                const cmp: compare.CompareResult = comparison(k, &self.keys[i]);
                if (cmp != .GreaterThan) {
                    return .{ .found = cmp == .Equal, .index = i };
                }
            }
            return .{ .found = false, .index = self.count };
        }
        /// Returns the index of k in keys if found
        /// Otherwise returns the index to insert the key at
        fn getInsertIndex(self: *TSelf, k: *const Tkey) usize {
            if (self.count == 0 or (comparison(k, &self.keys[0]) == .LessThan)) {
                return 0;
            }
            if (comparison(k, &self.keys[self.count - 1]) == .GreaterThan) {
                return self.count;
            }

            var low: isize = 1;
            var high: isize = @intCast(self.count - 2);
            var mid: isize = low + @divTrunc(high - low, 2);
            var midu: usize = @as(usize, @intCast(mid));
            while (low <= high and mid >= 0 and mid < self.keys.len) {
                const comp_left = comparison(k, &self.keys[midu - 1]);
                const comp_right = comparison(k, &self.keys[midu + 1]);
                if (comp_left == .LessThan and comp_right == .GreaterThan) {
                    return midu;
                }
                switch (comparison(&self.keys[midu], k)) {
                    .Equal => {
                        return midu;
                    },
                    .LessThan => {
                        low = mid + 1;
                    },
                    .GreaterThan => {
                        high = mid - 1;
                    },
                }
                mid = low + @divTrunc(high - low, 2);
                midu = @as(usize, @intCast(mid));
            }
            return midu;
        }
    };
}

/// A SortedArrayMap using numeric keys
pub fn AutoNumberSortedArrayMap(comptime Tkey: type, comptime Tval: type) type {
    return SortedArrayMap(Tkey, Tval, comptime compare.compareNumberFn(Tkey));
}
