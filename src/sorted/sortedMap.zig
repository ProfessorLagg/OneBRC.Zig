const builtin = @import("builtin");
const std = @import("std");
const compare = @import("compare.zig");

fn calc_default_initial_capacity(comptime Tkey: type, comptime Tval: type) comptime_int {
    // TODO this is only neccecary on targets with cachelines!
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
        const Self = @This();

        // === PUBLIC ===
        pub fn init(allocator: std.mem.Allocator) !Self {
            const result: Self = try initWithCapacity(allocator, default_initial_capacity);
            return result;
        }
        pub fn initWithCapacity(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            std.debug.assert(initial_capacity > 0);
            std.log.debug("initWithCapacity:\n\tallocator: {s}, initial_capacity: {d}", .{ @typeName(@TypeOf(allocator)), initial_capacity });
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
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.key_buffer);
            self.allocator.free(self.val_buffer);
        }
        /// Returns the number of values that can be contained before the backing arrays will be resized
        pub inline fn capacity(self: *Self) usize {
            std.debug.assert(self.key_buffer.len == self.val_buffer.len);
            return self.key_buffer.len;
        }
        /// Finds the index of the key. Returns -1 if not found
        pub fn indexOf(self: *Self, k: *const Tkey) isize {
            var L: isize = 0;
            var R: isize = @bitCast(self.count);
            R -= 1;
            while (L <= R) {
                const m = @divFloor(L + R, 2);
                const mu = @as(usize, @intCast(m));
                const cmp = comparison(&self.keys[mu], k);
                switch (cmp) {
                    .LessThan => L = m + 1,
                    .GreaterThan => R = m - 1,
                    .Equal => return m,
                }
            }
            return -1;
        }
        /// Returns true if k is found in self.keys. Otherwise false
        pub inline fn contains(self: *Self, k: Tkey) bool {
            const idx: isize = self.indexOf(k);
            std.log.debug("indexOf({any}) = {d}", .{ k, idx });
            return idx >= 0 and idx < self.keys.len;
        }
        /// Adds an item to the set.
        /// Returns true if the key could be added, otherwise false.
        pub fn add(self: *Self, k: *const Tkey, v: *const Tval) bool {
            if (self.contains(k)) {
                return false;
            }
            self.update(k, v);
            return true;
        }
        /// Overwrites the value at k, regardless of it's already contained
        pub fn update(self: *Self, k: *const Tkey, v: *const Tval) void {
            const insertionIndex = self.getInsertIndex(k);
            if (self.count == self.key_buffer.len) {
                const new_capacity: usize = self.capacity() * 2;
                self.resize(new_capacity);
            }
            self.insertAt(insertionIndex, k, v);
        }
        /// If k is in the map, updates the value at k using updateFn.
        /// otherwise add the value from addFn to the map
        pub fn addOrUpdate(self: *Self, k: Tkey, addFn: *const fn () Tval, updateFn: *const fn (*Tval) void) void {
            const idx: isize = self.indexOf(k);
            if (idx >= 0 or idx < self.count) {
                const idxu: usize = @intCast(idx);
                updateFn(&self.values[idxu]);
            } else {
                self.update(k, addFn());
            }
        }
        /// Reduces capacity to exactly fit count
        pub fn shrinkToFit(self: *Self) !void {
            // TODO shrinkToFit
            _ = &self;
        }

        // === PRIVATE ===
        /// Rezises capacity to newsize
        fn resize(self: *Self, new_capacity: usize) void {
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
        fn incrementCount(self: *Self) void {
            std.debug.assert(self.count < self.key_buffer.len);
            std.debug.assert(self.count < self.val_buffer.len);
            self.count += 1;
            self.keys = self.key_buffer[0..self.count];
            self.values = self.val_buffer[0..self.count];
            std.debug.assert(self.keys.len == self.count);
            std.debug.assert(self.values.len == self.count);
        }
        fn shiftRight(self: *Self, start_at: usize) void {
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
        fn insertAt(self: *Self, index: usize, k: *const Tkey, v: *const Tval) void {
            std.debug.assert(index <= self.count); // Does not get compiled in ReleaseFast and ReleaseSmall modes
            std.debug.assert(self.keys.len < self.key_buffer.len); // Does not get compiled in ReleaseFast and ReleaseSmall modes

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
        /// Returns the index this key would have if present in the map.
        fn getInsertIndex_old(self: *Self, k: *const Tkey) usize {
            if (self.count == 0) {
                return 0;
            }
            if (comparison(k, self.keys[0]) == .LessThan) {
                return 0;
            }
            if (comparison(k, self.keys[self.count - 1]) == .GreaterThan) {
                return self.count;
            }

            // TODO make this use binary search
            const l: usize = self.count - 1;
            for (1..l) |i| {
                const comp_i: compare.CompareResult = comparison(k, self.keys[i]);
                if (comp_i == .Equal) {
                    return i;
                }
                const comp_l: compare.CompareResult = comparison(k, self.keys[i - 1]);
                const comp_r: compare.CompareResult = comparison(k, self.keys[i + 1]);
                if (comp_l == .LessThan and comp_r == .GreaterThan) {
                    return i;
                }
            }
            return self.count;
        }

        /// Returns the index this key would have if present in the map.
        fn getInsertIndex(self: *Self, k: *const Tkey) usize {
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
