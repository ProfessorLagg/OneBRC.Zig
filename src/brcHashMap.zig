const builtin = @import("builtin");
const std = @import("std");
const MultiArrayList = std.MultiArrayList;
const utils = @import("utils.zig");

const sorted = @import("sorted/sorted.zig");

pub const BRCHashMap = struct {
    const Hashing = struct {
        const size8: comptime_int = size16 * 2;
        const size16: comptime_int = size32 * 2;
        const size32: comptime_int = size64 * 2;
        const size64: comptime_int = utils.math.divCiel(comptime_int, 100, @sizeOf(u64));

        pub fn hash8(str: []const u8) u8 {
            var r: u8 = 0;
            for (str) |n| r +%= n;
            return r;
        }

        fn combine16(a: u8, b: u8) u16 {
            const x: u16 = @intCast(a);
            const y: u16 = @intCast(b);
            // const maxxy: u16 = @max(x, y);
            // const n: u16 = maxxy * maxxy;
            // const m: u16 = @max(y, (2 * y) - x);
            // return n + m;
            return (x *% x) +% (y *% y *% y);
        }
        fn reduce16(str: []const u8) [size16]u16 {
            std.debug.assert(str.len <= comptime (size16 * 2));
            var result: [size16]u16 = undefined;
            var si: u8 = 0;
            var ri: u8 = 0;
            if (utils.math.isUneven(usize, str.len)) {
                result[0] = combine16(str[0], str[0]);
                si += 1;
                ri += 1;
            }

            while (si < str.len) : (si += 2) {
                result[ri] = combine16(str[si], str[si + 1]);
                ri += 1;
            }
            return result;
        }
        pub fn hash16(str: []const u8) u16 {
            std.debug.assert(str.len <= size8);
            const arr = reduce16(str);
            var r: u16 = 0;
            inline for (arr) |n| r +%= n;
            return r;
        }

        fn combine32(a: u16, b: u16) u32 {
            const x: u32 = @intCast(a);
            const y: u32 = @intCast(b);
            // const maxxy: u32 = @max(x, y);
            // const n: u32 = maxxy * maxxy;
            // const m: u32 = @max(y, (2 * y) - x);
            // return n + m;
            return (x *% x) +% (y *% y *% y);
        }
        fn reduce32(str: []const u8) [size32]u32 {
            const arr16 = reduce16(str);
            var result: [size32]u32 = undefined;
            var i: u8 = 0;
            while (i < arr16.len) : (i += 2) {
                result[i / 2] = combine32(arr16[i], arr16[i + 1]);
            }
            return result;
        }
        pub fn hash32(str: []const u8) u32 {
            std.debug.assert(str.len <= size8);
            const arr32 = reduce32(str);
            var r: u32 = 0;
            inline for (arr32) |n| r +%= n;
            return r;
        }

        fn combine64(a: u32, b: u32) u64 {
            const x: u64 = @intCast(a);
            const y: u64 = @intCast(b);
            // const maxxy: u64 = @max(x, y);
            // const n: u64 = maxxy * maxxy;
            // const m: u64 = @max(y, (2 * y) - x);
            // return n + m;
            return (x *% x) +% (y *% y *% y);
        }
        fn reduce64(str: []const u8) [size64]u64 {
            const arr32 = reduce32(str);
            var result: [size64]u64 = undefined;
            var i: u8 = 0;
            while (i < arr32.len) : (i += 2) {
                result[i / 2] = combine64(arr32[i], arr32[i + 1]);
            }
            return result;
        }
        pub fn hash64(str: []const u8) u64 {
            std.debug.assert(str.len <= size8);
            const arr64 = reduce64(str);
            var r: u64 = 0;
            inline for (arr64) |n| r +%= n;
            return r;
        }

        pub fn hash64_2(str: []const u8) u64 {
            var tmp: u64 = undefined;
            const tmpbytes: []u8 = std.mem.asBytes(&tmp);

            var i: usize = 0;
            var r: usize = 0;
            while (i < str.len) : (i += @sizeOf(usize)) {
                @memset(tmpbytes, 0);
                const s: []const u8 = str[i..];
                const l = @min(s.len, tmpbytes.len);
                @memcpy(tmpbytes[0..l], s[0..l]);
                r +%= tmp;
            }
            // std.log.debug("hash64_2(str: {s}) = 0x{X:0>16}", .{ str, r });
            return r;
        }
    };

    const Key = packed struct {
        ptr: usize,
        len: u8,

        pub fn fromString(str: []const u8) Key {
            const max_len: usize = comptime std.math.maxInt(u8);
            std.debug.assert(str.len <= max_len);
            return Key{
                .ptr = @intFromPtr(str.ptr),
                .len = @truncate(str.len),
            };
        }
        pub fn toString(self: *const Key) []const u8 {
            const ptr: [*]const u8 = @ptrFromInt(self.ptr);
            return ptr[0..self.len];
        }
        pub fn getHash(self: *const Key) u64 {
            // return Hashing.hash64(self.toString());
            return Hashing.hash64_2(self.toString());
        }
        pub fn toOwnedString(self: *const Key, allocator: std.mem.Allocator) ![]const u8 {
            const src: []const u8 = self.toString();
            const dst: []u8 = try allocator.alloc(u8, self.len);
            // std.log.debug("Key.toOwned alloced \"{s}\"", .{dst});
            std.mem.copyForwards(u8, dst, src);
            return dst;
        }
        pub fn toOwned(self: *const Key, allocator: std.mem.Allocator) !Key {
            nosuspend {
                return Key.fromString(try self.toOwnedString(allocator));
            }
        }
        pub fn stringEquals(self: *const Key, other: *const Key) bool {
            nosuspend {
                const strA: []const u8 = self.toString();
                const strB: []const u8 = other.toString();
                const l: u8 = @min(self.len, other.len);

                var i: usize = 0;
                var cmp: bool = strA.len != strB.len;
                while (!cmp and i < l) : (i += 1) {
                    cmp = strA[i] == strB[i];
                }
                return cmp;
            }
        }
    };

    const Val = packed struct {
        const TSelf = @This();
        count: u32 = 0,
        sum: i64 = 0,

        pub fn init(val: i64) TSelf {
            return TSelf{
                .count = 1,
                .sum = val,
            };
        }

        pub fn merge(a: TSelf, b: TSelf) TSelf {
            return TSelf{ .count = a.count + b.count, .sum = a.sum + b.sum };
        }
        pub fn mergeR(self: *TSelf, other: *const TSelf) void {
            self.count += other.count;
            self.sum += other.sum;
        }

        pub fn add(self: *TSelf, val: i64) void {
            self.count += 1;
            self.sum += val;
        }
    };

    const KVP = struct {
        key: Key,
        val: Val,
    };

    const SortedMap = sorted.SSOSortedArrayMap(Val);

    const Bucket = struct {
        allocator: std.mem.Allocator,
        lock: std.Thread.Mutex = .{},

        // TODO i can save a lot of space by only storing the buffer pointers, capacity and len
        buf_keys: []Key = undefined,
        keys: []Key = undefined,

        buf_hashes: []u64 = undefined,
        hashes: []u64 = undefined,

        buf_values: []Val = undefined,
        values: []Val = undefined,

        pub fn init(allocator: std.mem.Allocator) !Bucket {
            var self: Bucket = Bucket{ .allocator = allocator };
            errdefer self.deinit();

            self.buf_keys = try self.allocator.alloc(Key, 1);
            self.keys = self.buf_keys[0..0];

            self.buf_hashes = try self.allocator.alloc(u64, 1);
            self.hashes = self.buf_hashes[0..0];

            self.buf_values = try self.allocator.alloc(Val, 1);
            self.values = self.buf_values[0..0];

            return self;
        }
        pub fn deinit(self: *Bucket) void {
            for (self.keys) |*k| self.allocator.free(k.toString());

            self.allocator.free(self.buf_keys);
            self.allocator.free(self.buf_hashes);
            self.allocator.free(self.buf_values);
            self.* = undefined;
        }

        fn grow(self: *Bucket) !void {
            const old_capacity: usize = self.buf_keys.len;
            const new_capacity: usize = @max(1, old_capacity * 2);
            const l: usize = self.keys.len;

            self.buf_keys = try self.allocator.realloc(self.buf_keys, new_capacity);
            self.buf_hashes = try self.allocator.realloc(self.buf_hashes, new_capacity);
            self.buf_values = try self.allocator.realloc(self.buf_values, new_capacity);

            self.keys = self.buf_keys[0..l];
            self.hashes = self.buf_hashes[0..l];
            self.values = self.buf_values[0..l];
        }
        fn ensureCanAddOne(self: *Bucket) !void {
            const len: usize = self._len();
            const capacity: usize = self._capacity();
            std.debug.assert(len <= capacity);
            if (self._len() == self._capacity()) try self.grow();
        }

        fn _capacity(self: *const Bucket) usize {
            std.debug.assert(self.buf_hashes.len == self.buf_keys.len);
            std.debug.assert(self.buf_values.len == self.buf_keys.len);
            return self.buf_keys.len;
        }

        fn _len(self: *const Bucket) usize {
            // std.log.debug("Bucket._len: keys.len: {d}, hashes.len: {d}, values.len: {d}", .{ self.keys.len, self.hashes.len, self.values.len });
            std.debug.assert(self.hashes.len == self.keys.len);
            std.debug.assert(self.values.len == self.keys.len);
            return self.keys.len;
        }

        fn find(self: *const Bucket, key: Key, hash: u64) ?usize {
            var match_indexes: [std.heap.page_size_min / @sizeOf(u32)]u32 = undefined;
            var macth_count: usize = 0;
            for (0..self.hashes.len, self.hashes) |i, h| {
                const match: u8 = @intFromBool(hash == h);
                match_indexes[macth_count] = @intCast(i * match);
                macth_count += match;
            }
            for (match_indexes[0..macth_count]) |i| if (key.stringEquals(&self.keys[i])) return i;
            return null;
        }
        fn addOne(self: *Bucket) !usize {
            const result: usize = self.keys.len;
            try self.ensureCanAddOne();
            self.keys.len += 1;
            self.hashes.len = self.keys.len;
            self.values.len = self.keys.len;
            return result;
        }
        pub fn addOrUpdate(self: *Bucket, keystr: []const u8, valint: i64) !void {
            self.lock.lock();
            nosuspend {
                const refkey: Key = Key.fromString(keystr);
                const hash: u64 = refkey.getHash();
                if (self.find(refkey, hash)) |index| {
                    // The key was found
                    self.values[index].add(valint);
                } else {
                    // The key was not found
                    const index = try self.addOne();
                    self.keys[index] = try refkey.toOwned(self.allocator);
                    self.hashes[index] = hash;
                    self.values[index] = Val.init(valint);
                }
            }
            self.lock.unlock();
        }
        pub fn get(self: *const Bucket, index: usize) ?KVP {
            if (index >= self._len()) {
                @branchHint(.cold);
                return null;
            }

            return KVP{
                .key = self.keys[index],
                .val = self.values[index],
            };
        }
    };

    allocator: std.mem.Allocator,
    buckets: []Bucket,

    pub fn init(allocator: std.mem.Allocator) !BRCHashMap {
        var self = BRCHashMap{
            .allocator = allocator,
            .buckets = try allocator.alloc(Bucket, 100),
        };
        for (0..self.buckets.len) |i| {
            self.buckets[i] = try Bucket.init(self.allocator);
        }
        return self;
    }
    pub fn deinit(self: *BRCHashMap) void {
        for (0..self.buckets.len) |i| self.buckets[i].deinit();
    }

    pub fn addOrUpdate(self: *BRCHashMap, keystr: []const u8, val: i64) !void {
        // std.log.debug("addOrUpdate(key: \"{s}\", val: {d})", .{ keystr, val });
        const bucketId = self.buckets.len & keystr.len;
        self.buckets[bucketId].addOrUpdate(keystr, val) catch |err| {
            @branchHint(.cold);
            return err;
        };
    }

    pub fn toSortedMap(self: *const BRCHashMap) !SortedMap {
        var sortedMap: SortedMap = SortedMap.init(self.allocator) catch |err| {
            @branchHint(.cold);
            return err;
        };
        for (0..self.buckets.len, self.buckets) |bucketId, bucket| {
            std.log.debug("adding bucket {d} to SortedMap = {any}", .{ bucketId, bucket });

            for (0..bucket._len()) |i| {
                std.log.debug("adding kvp {d} to SortedMap", .{i});
                if (bucket.get(i)) |kvp| {
                    @branchHint(.likely);
                    const keystr: []const u8 = kvp.key.toString();
                    std.log.debug("kvp data = key: \"{s}\", val: {any} to SortedMap", .{ keystr, kvp.val });
                    sortedMap.addOrUpdateString(keystr, &kvp.val, Val.mergeR);
                }
            }
        }
        return sortedMap;
    }

    /// Deinits the BRCHashMap, and returns a SortedMap with the key/value pairs
    pub fn finalize(self: *BRCHashMap) !SortedMap {
        const sortedMap = try self.toSortedMap();
        self.deinit();
        return sortedMap;
    }
};
