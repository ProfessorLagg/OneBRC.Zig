const builtin = @import("builtin");
const std = @import("std");
const Int = std.meta.Int;

const structSize: comptime_int = @sizeOf(usize) + @sizeOf([*]u8);
const structBitSize: comptime_int = @bitSizeOf(usize) + @bitSizeOf([*]u8);
const maxStackLen: comptime_int = structSize - @sizeOf(u8);
const maxStackBitLen: comptime_int = structBitSize - @bitSizeOf(u8);

const StackString = packed struct {
    const TUInt: type = Int(.unsigned, maxStackBitLen);
    len: u8 = 0,
    val: TUInt = 0,

    inline fn toSliceC(self: *const StackString) []const u8 {
        return b: {
            var r: []const u8 = undefined;
            r.len = self.len;
            r.ptr = @ptrFromInt(@intFromPtr(self) + 1);
            break :b r;
        };
    }

    inline fn toSlice(self: *StackString) []u8 {
        return b: {
            var r: []u8 = undefined;
            r.len = self.len;
            r.ptr = @ptrFromInt(@intFromPtr(self) + 1);
            break :b r;
        };
    }

    fn initClone(str: []const u8) StackString {
        std.debug.assert(str.len <= maxStackLen);
        var r: StackString = .{};
        r.len = @truncate(str.len);
        const slice = r.toSlice();
        @memcpy(slice, str);
        return r;
    }

    fn deinit(self: *StackString) void {
        self.len = 0;
        self.val = 0;
    }
};

const HeapString = packed struct {
    const staticAllocator: std.mem.Allocator = b: {
        if (builtin.is_test) break :b std.testing.allocator;
        if (!builtin.single_threaded) break :b std.heap.smp_allocator;
        if (builtin.link_libc) break :b std.heap.c_allocator;
        @compileError("Requires either single-threading to be disabled or lib-c to be linked");
    };

    len: usize = 0,
    ptr: [*]u8 = undefined,

    inline fn toSliceC(self: *const HeapString) []const u8 {
        return self.ptr[0..self.len];
    }

    inline fn toSlice(self: *HeapString) []u8 {
        return self.ptr[0..self.len];
    }

    fn init(size: usize) !HeapString {
        std.debug.assert(size > maxStackLen);
        const s: []u8 = try staticAllocator.alloc(u8, size);
        return HeapString{
            .len = s.len,
            .ptr = s.ptr,
        };
    }

    fn initClone(str: []const u8) !HeapString {
        const s: []u8 = try staticAllocator.alloc(u8, str.len);
        @memcpy(s[0..], str);

        return HeapString{
            .len = s.len,
            .ptr = s.ptr,
        };
    }

    fn initRef(str: []const u8) HeapString {
        // TODO Support for un-owned heap strings
        _ = str;
        @compileError("Not Implemented");
    }

    fn deinit(self: *HeapString) void {
        staticAllocator.free(self.toSliceC());
        self.len = 0;
        self.ptr = undefined;
    }
};

pub const String = packed union {
    stack: StackString,
    heap: HeapString,

    pub inline fn isHeapString(self: *const String) bool {
        return self.stack.len > maxStackLen;
    }

    pub inline fn isStackString(self: *const String) bool {
        return self.stack.len <= maxStackLen;
    }

    pub fn initClone(str: []const u8) String {
        if (str.len <= maxStackLen) {
            return String{ .stack = StackString.initClone(str) };
        } else {
            return String{ .heap = HeapString.initClone(str) catch |e| std.debug.panic("{any}{any}", .{ e, @errorReturnTrace() }) };
        }
    }

    pub fn deinit(self: *String) void {
        if (self.isHeapString()) {
            self.heap.deinit();
        } else {
            self.stack.deinit();
        }
    }

    pub fn toSlice(self: *String) []u8 {
        if (self.isStackString()) return self.stack.toSlice();
        return self.heap.toSlice();
    }

    pub fn toSliceC(self: *const String) []const u8 {
        if (self.isStackString()) return self.stack.toSliceC();
        return self.heap.toSliceC();
    }

    pub inline fn len(self: *const String) usize {
        const isStack: bool = self.isStackString();
        const s_mul: u8 = @intFromBool(isStack);
        const s_len: u8 = s_mul * self.stack.len;
        const h_mul: usize = @intFromBool(!isStack);
        const h_len: usize = h_mul * self.heap.len;
        return s_len + h_len;
    }

    /// Checks equality of struct data.
    /// For StackString this is equivalent to `a.len == b.len and a.val == b.val`
    /// For HeapString this is equivalent to `a.len == b.len and @intFromPtr(a.ptr) == @intFromPtr(b.ptr)`
    fn eql_struct(a: *const String, b: *const String) bool {
        return a.heap.len == b.heap.len and @intFromPtr(a.heap.ptr) == @intFromPtr(b.heap.ptr);
    }
    /// Checks equality between 2 heap strings
    fn eql_heap(a: *const String, b: *const String) bool {
        std.debug.assert(a.isHeapString());
        std.debug.assert(b.isHeapString());
        // TODO i know thers a faster way to do this, since i already know that the slices are longer than maxStackLen
        return std.mem.eql(u8, a.heap.toSliceC(), b.heap.toSliceC());
    }
    pub fn eql(a: *const String, b: *const String) bool {
        if (@intFromPtr(a) == @intFromPtr(b)) return true;
        const a_isStack: bool = a.isStackString();
        const b_isStack: bool = b.isStackString();
        // since a HeapString is always longer than a StackString, StackStrings and HeapStrings can never be equal
        if (a_isStack != b_isStack) return false;

        const eql_stc: bool = eql_struct(a, b);
        // if HeapStrings has the same struct data, they also have the same content
        // StackString content is the same as StackString struct data.
        if (eql_stc or a_isStack) return eql_stc;

        // To reach here means i have 2 HeapStrings with different struct data
        return eql_heap(a, b);
    }

    fn compare_uint(T: type, a: T, b: T) i8 {
        comptime {
            const ti: std.builtin.Type = @typeInfo(T);
            if (ti != .int) unreachable;
            if (ti.int.signedness != .unsigned) unreachable;
        }

        const lt: i8 = @intFromBool(a < b) * @as(i8, -1); // -1 if true, 0 if false
        const gt: i8 = @intFromBool(a > b); // 1 if true, 0 if false
        return lt + gt;
    }

    /// compare 2 strings for sorting purposes.
    /// returns -1 if a < b, 0 if a == b and return 1 for a > b
    pub fn compare(a: *const String, b: *const String) i8 {
        if (@intFromPtr(a) == @intFromPtr(b)) return 0;
        const a_len: usize = a.len();
        const b_len: usize = b.len();
        const a_slice = a.toSliceC();
        const b_slice = b.toSliceC();
        var cmp: i8 = compare_uint(usize, a_len, b_len);
        var i: usize = 0;

        while (cmp == 0 and i < a_len) : (i += 1) cmp = compare_uint(u8, a_slice[i], b_slice[i]);
        return std.math.sign(cmp);
    }

    test initClone {
        var arrStr: [maxStackLen * 2]u8 = undefined;
        const slcL: []u8 = arrStr[0..];
        const slcS: []u8 = arrStr[0 .. maxStackLen - 1];
        @memset(slcL, 'A');

        var str_heap = String.initClone(slcL);
        defer str_heap.deinit();
        try std.testing.expect(str_heap.isHeapString());
        try std.testing.expectEqualStrings(slcL, str_heap.toSliceC());
        try std.testing.expectEqualStrings(slcL, str_heap.toSlice());

        var str_stack = String.initClone(slcS);
        defer str_stack.deinit();
        try std.testing.expect(str_stack.isStackString());
        try std.testing.expectEqualStrings(slcS, str_stack.toSliceC());
        try std.testing.expectEqualStrings(slcS, str_stack.toSlice());
    }

    test eql {
        var arr_A: [maxStackLen * 2]u8 = undefined;
        const slcL_A: []u8 = arr_A[0..];
        const slcS_A: []u8 = arr_A[0 .. maxStackLen - 1];
        @memset(slcL_A, 'A');

        var arr_B: [maxStackLen * 2]u8 = undefined;
        const slcL_B: []u8 = arr_B[0..];
        const slcS_B: []u8 = arr_B[0 .. maxStackLen - 1];
        @memset(slcL_B, 'B');

        var str_h_1 = String.initClone(slcL_A);
        var str_s_1 = String.initClone(slcS_A);
        var str_h_2 = String.initClone(slcL_B);
        var str_s_2 = String.initClone(slcS_B);
        var str_h_3 = String.initClone(slcL_A);
        var str_s_3 = String.initClone(slcS_A);
        defer str_h_1.deinit();
        defer str_s_1.deinit();
        defer str_h_2.deinit();
        defer str_s_2.deinit();
        defer str_h_3.deinit();
        defer str_s_3.deinit();

        try std.testing.expect(str_h_1.isHeapString());
        try std.testing.expect(str_s_1.isStackString());
        try std.testing.expect(str_h_2.isHeapString());
        try std.testing.expect(str_s_2.isStackString());
        try std.testing.expect(str_h_3.isHeapString());
        try std.testing.expect(str_s_3.isStackString());

        try std.testing.expectEqual(true, str_h_1.eql(&str_h_1));
        try std.testing.expectEqual(false, str_h_1.eql(&str_s_1));
        try std.testing.expectEqual(false, str_h_1.eql(&str_h_2));
        try std.testing.expectEqual(false, str_h_1.eql(&str_s_2));
        try std.testing.expectEqual(true, str_h_1.eql(&str_h_3));
        try std.testing.expectEqual(false, str_h_1.eql(&str_s_3));
        try std.testing.expectEqual(false, str_s_1.eql(&str_h_1));
        try std.testing.expectEqual(true, str_s_1.eql(&str_s_1));
        try std.testing.expectEqual(false, str_s_1.eql(&str_h_2));
        try std.testing.expectEqual(false, str_s_1.eql(&str_s_2));
        try std.testing.expectEqual(false, str_s_1.eql(&str_h_3));
        try std.testing.expectEqual(true, str_s_1.eql(&str_s_3));
        try std.testing.expectEqual(false, str_h_2.eql(&str_h_1));
        try std.testing.expectEqual(false, str_h_2.eql(&str_s_1));
        try std.testing.expectEqual(true, str_h_2.eql(&str_h_2));
        try std.testing.expectEqual(false, str_h_2.eql(&str_s_2));
        try std.testing.expectEqual(false, str_h_2.eql(&str_h_3));
        try std.testing.expectEqual(false, str_h_2.eql(&str_s_3));
        try std.testing.expectEqual(false, str_s_2.eql(&str_h_1));
        try std.testing.expectEqual(false, str_s_2.eql(&str_s_1));
        try std.testing.expectEqual(false, str_s_2.eql(&str_h_2));
        try std.testing.expectEqual(true, str_s_2.eql(&str_s_2));
        try std.testing.expectEqual(false, str_s_2.eql(&str_h_3));
        try std.testing.expectEqual(false, str_s_2.eql(&str_s_3));
        try std.testing.expectEqual(true, str_h_3.eql(&str_h_1));
        try std.testing.expectEqual(false, str_h_3.eql(&str_s_1));
        try std.testing.expectEqual(false, str_h_3.eql(&str_h_2));
        try std.testing.expectEqual(false, str_h_3.eql(&str_s_2));
        try std.testing.expectEqual(true, str_h_3.eql(&str_h_3));
        try std.testing.expectEqual(false, str_h_3.eql(&str_s_3));
        try std.testing.expectEqual(false, str_s_3.eql(&str_h_1));
        try std.testing.expectEqual(true, str_s_3.eql(&str_s_1));
        try std.testing.expectEqual(false, str_s_3.eql(&str_h_2));
        try std.testing.expectEqual(false, str_s_3.eql(&str_s_2));
        try std.testing.expectEqual(false, str_s_3.eql(&str_h_3));
        try std.testing.expectEqual(true, str_s_3.eql(&str_s_3));
    }
};

pub fn SortedStringMap(comptime T: type) type {
    return struct {
        const TSelf = @This();

        allocator: std.mem.Allocator,

        key_buffer: []String = undefined,
        val_buffer: []T = undefined,

        keys: []String = undefined,
        vals: []T = undefined,

        pub fn init(allocator: std.mem.Allocator) TSelf {
            var r = TSelf{ .allocator = allocator };
            r.key_buffer.len = 0;
            r.val_buffer.len = 0;
            r.keys = r.key_buffer[0..0];
            r.vals = r.val_buffer[0..0];
            return r;
        }

        pub fn deinit(self: *TSelf) void {
            for (self.keys) |*k| k.deinit();
            self.allocator.free(self.key_buffer);
            self.allocator.free(self.val_buffer);
        }

        /// Returns the number of currently stored items
        pub inline fn len(self: *const TSelf) usize {
            std.debug.assert(self.keys.len == self.vals.len);
            return self.keys.len;
        }

        /// Returns the number of items that can be stored before buffers resize
        pub inline fn capacity(self: *const TSelf) usize {
            std.debug.assert(self.key_buffer.len == self.val_buffer.len);
            return self.key_buffer.len;
        }

        fn ensureCapacity_old(self: *TSelf, new_capacity: usize) !void {
            const old_size = self.capacity();
            if (old_size >= new_capacity) return;

            if (old_size == 0) {
                self.key_buffer = try self.allocator.alloc(String, 1);
                self.val_buffer = try self.allocator.alloc(T, 1);
                self.keys = self.key_buffer[0..self.keys.len];
                self.vals = self.val_buffer[0..self.vals.len];
                try self.ensureCapacity(new_capacity);
                return;
            }

            const new_size = try std.math.ceilPowerOfTwo(usize, new_capacity);
            const new_key_buffer: []String = try self.allocator.alloc(String, new_size);
            const new_val_buffer: []T = try self.allocator.alloc(T, new_size);

            @memcpy(new_key_buffer[0..self.keys.len], self.keys[0..]);
            @memcpy(new_val_buffer[0..self.vals.len], self.vals[0..]);
            self.allocator.free(self.key_buffer);
            self.allocator.free(self.val_buffer);
            self.key_buffer = new_key_buffer;
            self.val_buffer = new_val_buffer;
            self.keys = self.key_buffer[0..self.keys.len];
            self.vals = self.val_buffer[0..self.vals.len];
        }

        fn ensureCapacity(self: *TSelf, new_capacity: usize) !void {
            const old_size = self.capacity();
            if (old_size >= new_capacity) return;

            if (old_size == 0) {
                self.key_buffer = try self.allocator.alloc(String, 1);
                self.val_buffer = try self.allocator.alloc(T, 1);
                self.keys = self.key_buffer[0..self.keys.len];
                self.vals = self.val_buffer[0..self.vals.len];
                try self.ensureCapacity(new_capacity);
                return;
            }

            const new_size = try std.math.ceilPowerOfTwo(usize, new_capacity);

            if (self.allocator.resize(self.key_buffer, new_size)) self.key_buffer.len = new_size else self.key_buffer = try self.allocator.realloc(self.key_buffer, new_size);
            if (self.allocator.resize(self.val_buffer, new_size)) self.val_buffer.len = new_size else self.val_buffer = try self.allocator.realloc(self.val_buffer, new_size);
            self.keys = self.key_buffer[0..self.keys.len];
            self.vals = self.val_buffer[0..self.vals.len];
        }

        fn binarySearch(self: *const TSelf, key: *const String) ?usize {
            var low: usize = 0;
            var high: usize = self.len();
            while (low < high) {
                const mid = low + (high - low) / 2;
                const cmp = key.compare(&self.key_buffer[mid]);
                switch (cmp) {
                    0 => return mid,
                    1 => low = mid + 1,
                    -1 => high = mid,
                    else => unreachable,
                }
            }
            return null;
        }

        pub fn put(self: *TSelf, key: []const u8, val: T) !void {
            const ptr: *T = try self.findOrInsert(key);
            ptr.* = val;
        }

        /// Returns a pointer to the value associated with `key`.
        /// If `key` is not found in the map, returns null
        pub fn find(self: *const TSelf, key: []const u8) ?*T {
            const k = String.initClone(key);
            defer k.deinit();
            if (self.binarySearch(key)) |i| return &self.vals[i];
            return null;
        }

        /// Returns a pointer to the value associated with `key`.
        /// If `key` is not found in the map, inserts it and returns a pointer to the new value.
        /// Warning! Incase the buffers need to be resized to fit the new key/value pair, all old key/value pointers are invalidated.
        pub fn findOrInsert(self: *TSelf, key: []const u8) !*T {
            var k = String.initClone(key);

            const old_len = self.len();
            if (old_len == 0) {
                try self.ensureCapacity(1);
                self.key_buffer[0] = k;
                self.val_buffer[0] = undefined;
                self.keys = self.key_buffer[0..1];
                self.vals = self.val_buffer[0..1];
                return &self.vals[0];
            }

            var low: usize = 0;
            var high: usize = old_len;
            var mid: usize = undefined;
            var cmp: i8 = undefined;
            while (low < high) {
                mid = low + (high - low) / 2;
                cmp = k.compare(&self.keys[mid]);
                switch (cmp) {
                    0 => {
                        // Key was found
                        k.deinit();
                        return &self.vals[mid];
                    },
                    1 => low = mid + 1,
                    -1 => high = mid,
                    else => unreachable,
                }
            }

            // Key was not found
            try self.ensureCapacity(old_len + 1);
            if (cmp == -1) {
                while (cmp < 0 and mid > 0) {
                    mid -= 1;
                    cmp = k.compare(&self.keys[mid]);
                }
            } else if (cmp == 1) {
                while (cmp > 0 and mid < old_len - 1) {
                    mid += 1;
                    cmp = k.compare(&self.keys[mid]);
                }
            } else {
                std.log.debug("Expected 1 or -1, but found {d}", .{cmp});
                unreachable;
            }

            var i: usize = old_len;
            while (i > mid) : (i -= 1) {
                self.key_buffer[i] = self.key_buffer[i - 1];
                self.val_buffer[i] = self.val_buffer[i - 1];
            }
            self.key_buffer[mid] = k;
            self.val_buffer[mid] = undefined;
            self.keys.len += 1;
            self.vals.len += 1;
            return &self.vals[mid];
        }

        test put {
            // TODO Test that all the inserted values are actually in the map and in the correct positions

            var ssm: TSelf = TSelf.init(std.testing.allocator);
            defer ssm.deinit();

            var prng = std.Random.DefaultPrng.init(2025_07_06);
            var val: T = undefined;
            const valbuf: []u8 = std.mem.asBytes(&val);

            inline for (0..101) |i| {
                @memset(valbuf, 0);
                prng.fill(valbuf);
                const keystr: []const u8 = try std.fmt.allocPrint(std.testing.allocator, "k{d}", .{i});
                try ssm.put(keystr, val);
                std.testing.allocator.free(keystr);
            }
        }
    };
}

test "Size and Alignment" {
    try std.testing.expectEqual(structSize, @sizeOf(StackString));
    try std.testing.expectEqual(structSize, @sizeOf(HeapString));
    try std.testing.expectEqual(@alignOf(StackString), @alignOf(HeapString));
    std.log.debug("{s} | size: {d}, align: {d}", .{ @typeName(StackString), @sizeOf(StackString), @alignOf(StackString) });
    std.log.debug("{s} | size: {d}, align: {d}", .{ @typeName(HeapString), @sizeOf(HeapString), @alignOf(HeapString) });
    std.log.debug("{s} | size: {d}, align: {d}", .{ @typeName(String), @sizeOf(String), @alignOf(String) });
}

test "Length" {
    var str: String = .{ .stack = .{} };
    for (0..256) |i| {
        str.stack.len = 0;
        str.heap.len = i;
        try std.testing.expectEqual(i, str.stack.len);

        str.heap.len = 0;
        str.stack.len = @truncate(i);
        try std.testing.expectEqual(i, str.heap.len);
    }

    for (256..512) |i| {
        str.stack.len = 0;
        str.heap.len = i;
        try std.testing.expect(str.heap.len != @as(@TypeOf(str.heap.len), @intCast(str.stack.len)));
    }
}

test "std.math.cielPowerOfTwo" {
    var i: usize = 1;
    while (i < 65_356) {
        const next_i: usize = i * 2;
        try std.testing.expectEqual(next_i, std.math.ceilPowerOfTwo(usize, i + 1));
        i = next_i;
    }
}

test StackString {
    const arrStr = "test";
    const slcStr: []const u8 = arrStr[0..];

    var str: StackString = StackString.initClone(slcStr);
    try std.testing.expectEqualStrings(slcStr, str.toSliceC());
    try std.testing.expectEqualStrings(slcStr, str.toSlice());
}

test HeapString {
    const arrStr = "TestTestTest";
    const slcStr: []const u8 = arrStr[0..];

    var str: HeapString = try HeapString.initClone(slcStr);
    defer str.deinit();
    try std.testing.expectEqualStrings(slcStr, str.toSliceC());
    try std.testing.expectEqualStrings(slcStr, str.toSlice());
}

test String {
    _ = String;
}

test SortedStringMap {
    _ = SortedStringMap(usize);
    _ = SortedStringMap(u8);
    _ = SortedStringMap(u64);
    _ = SortedStringMap(u32);
    _ = SortedStringMap(u16);
    _ = SortedStringMap(u128);
    _ = SortedStringMap(isize);
    _ = SortedStringMap(i8);
    _ = SortedStringMap(i64);
    _ = SortedStringMap(i32);
    _ = SortedStringMap(i16);
    _ = SortedStringMap(i128);
    _ = SortedStringMap(f80);
    _ = SortedStringMap(f64);
    _ = SortedStringMap(f32);
    _ = SortedStringMap(f16);
    _ = SortedStringMap(f128);
    _ = SortedStringMap(@Vector(70, f32));
    _ = SortedStringMap(struct { sum: u32 = 0, count: u32 = 0 });
}
