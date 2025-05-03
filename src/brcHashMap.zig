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
    };

    const TKey = packed struct {
        const TSelf = @This();
        const THash = u64;
        // ptr: [*]const u8,
        ptr: usize,
        len: u8,
        hsh: THash,

        inline fn getHash(str: []const u8) THash {
            return Hashing.hash64(str);
        }
        pub fn init(allocator: std.mem.Allocator, keystr: []const u8) !TSelf {
            std.debug.assert(keystr.len <= 100);
            const str: []u8 = try allocator.alloc(u8, keystr.len);
            std.mem.copyForwards(u8, str, keystr);
            return TSelf{
                .ptr = @intFromPtr(str.ptr),
                .len = @truncate(str.len),
                .hsh = getHash(str),
            };
        }
        pub fn deinit(self: *TSelf, allocator: std.mem.Allocator) void {
            allocator.free(self.asString());
        }
        pub fn wrap(str: []const u8) TSelf {
            std.debug.assert(str.len <= 100);
            return TSelf{
                .ptr = @intFromPtr(str.ptr),
                .len = @truncate(str.len),
                .hsh = getHash(str),
            };
        }
        pub fn clone(self: *const TSelf, allocator: std.mem.Allocator) !TSelf {
            const src_str: []const u8 = self.asString();
            const dst_str: []u8 = try allocator.alloc(u8, src_str.len);
            std.mem.copyForwards(u8, dst_str, src_str);
            return TSelf{
                .ptr = @intFromPtr(dst_str.ptr),
                .len = @truncate(dst_str.len),
                .hsh = self.hsh,
            };
        }
        pub fn asString(self: *const TSelf) []const u8 {
            const ptr: [*]const u8 = @ptrFromInt(self.ptr);
            return ptr[0..self.len];
        }
        pub fn bucketId(self: *const TKey, comptime bucketCount: u64) u64 {
            return self.len % bucketCount;
        }
        pub fn eql(a: *const TSelf, b: *const TSelf) bool {
            const astr = a.asString();
            const bstr = b.asString();
            if (astr.len != bstr.len) {
                @branchHint(.cold);
                return false;
            }
            std.debug.assert(astr.len == bstr.len);

            for (astr, bstr) |ac, bc| if (ac != bc) return false;
            return true;
        }
    };

    const TVal = packed struct {
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
        key: TKey,
        val: TVal,
    };

    const SortedMap = sorted.SSOSortedArrayMap(TVal);
    base_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    buckets: [100]MultiArrayList(KVP),

    pub fn init(allocator: std.mem.Allocator) BRCHashMap {
        var r = BRCHashMap{
            .base_allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .allocator = undefined,
            .buckets = undefined,
        };
        r.allocator = r.arena.allocator();
        for (0..r.buckets.len) |i| r.buckets[i] = MultiArrayList(KVP){};
        return r;
    }
    pub fn deinit(self: *BRCHashMap) void {
        for (0..self.buckets.len) |i| {
            for (self.buckets[i].items(.key)) |*k| k.deinit(self.allocator);
            self.buckets[i].deinit(self.allocator);
        }
        self.arena.deinit();
    }

    fn indexOfKey(bucket: *const MultiArrayList(KVP), key: TKey) ?usize {
        for (bucket.items(.key), 0..bucket.len) |*bkey, i| {
            if (bkey.hsh == key.hsh) {
                if (key.eql(bkey)) {
                    return i;
                }
            }
        }
        return null;
    }
    fn addToBucket(allocator: std.mem.Allocator, bucket: *MultiArrayList(KVP), kvp: KVP) !void {
        if (bucket.len <= bucket.capacity) {
            const old_capacity = bucket.capacity;
            const new_capacity = std.math.clamp(old_capacity * 2, 2, std.math.maxInt(usize));
            try bucket.setCapacity(allocator, new_capacity);
            std.debug.assert(bucket.capacity == new_capacity);
        }
        const prelen = bucket.len;
        const index = bucket.addOneAssumeCapacity();
        const postlen = bucket.len;
        std.debug.assert(postlen > prelen);
        bucket.set(index, kvp);
    }
    pub fn addOrUpdate(self: *BRCHashMap, keystr: []const u8, val: i64) !void {
        std.log.debug("addOrUpdate(key: \"{s}\", val: {d})", .{ keystr, val });
        const key = TKey.wrap(keystr);
        const bucketId = key.bucketId(self.buckets.len);
        var bucket = self.buckets[bucketId];
        const idx = indexOfKey(&bucket, key);
        if (idx == null) {
            const kvp = KVP{
                // .key = try TKey.init(self.allocator, keystr),
                .key = key,
                .val = TVal.init(val),
            };
            const index = try bucket.addOne(self.allocator);
            bucket.set(index, kvp);
            // try addToBucket(self.allocator, &bucket, kvp);
        } else {
            bucket.items(.val)[idx.?].add(val);
        }
    }

    pub fn toSortedMap(self: *const BRCHashMap) !SortedMap {
        var r: SortedMap = SortedMap.init(self.base_allocator) catch |err| {
            @branchHint(.cold);
            return err;
        };
        for (0..self.buckets.len) |bucketId| {
            const bucket: *const MultiArrayList(KVP) = &self.buckets[bucketId];
            std.log.debug("adding bucket {d} to SortedMap = {any}", .{ bucketId, bucket });

            for (0..bucket.len) |i| {
                std.log.debug("adding kvp {d} to SortedMap", .{i});
                const kvp: KVP = bucket.get(i);
                const keystr: []const u8 = kvp.key.asString();
                std.log.debug("  kvp data = key: \"{s}\", val: {any} to SortedMap", .{ keystr, kvp.val });
                r.addOrUpdateString(keystr, &kvp.val, TVal.mergeR);
            }
        }
        return r;
    }

    /// Deinits the BRCHashMap, and returns a SortedMap with the key/value pairs
    pub fn finalize(self: *BRCHashMap) !SortedMap {
        const r = try self.toSortedMap();
        self.deinit();
        return r;
    }
};
