const builtin = @import("builtin");
const std = @import("std");
const BRCMap = @import("BRCmap.zig");
const MapVal = BRCMap.MapVal;
const MapEntry = BRCMap.MapEntry;
const ut = @import("utils.zig");

pub fn BRCBucketMap(comptime bucket_count: comptime_int) type {
    return struct {
        const Self = @This();
        arena: std.heap.ArenaAllocator,
        allocator: std.mem.Allocator,
        buckets: [bucket_count]BRCMap,

        fn calcBucketIndex(key: []const u8) usize {
            @setRuntimeSafety(false);
            const sum: usize = ut.math.sumBytes(key);
            const idx: usize = (key.len +% sum) % bucket_count;
            std.debug.assert(idx < bucket_count);
            std.log.debug("calcBucketIndex(\"{s}\") = {d} / {d}", .{ key, idx, bucket_count - 1 });
            return idx;
        }
        /// Initializes just the `arena` and `allocator` fields, leavingh the `buckets` field as undefined
        fn initBase(allocator: std.mem.Allocator) Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            return Self{
                .arena = arena,
                .allocator = arena.allocator(),
                .buckets = undefined,
            };
        }
        pub fn init(allocator: std.mem.Allocator) !Self {
            var r: Self = initBase(allocator);
            inline for (0..bucket_count) |i| r.buckets[i] = BRCMap.init(allocator);
            return r;
        }
        pub fn deinit(self: *Self) void {
            inline for (0..bucket_count) |i| self.buckets[i].deinit(); // TODO Test if this is even neccecary
            self.arena.deinit();
        }

        pub fn findBucket(self: *Self, key: []const u8) *BRCMap {
            return &self.buckets[calcBucketIndex(key)];
        }

        pub fn findOrInsert(self: *Self, key: []const u8) !*MapVal {
            return try self.buckets[calcBucketIndex(key)].findOrInsert(key);
        }

        /// Joins all the buckets into a single map, using the input allocator, and frees self
        pub fn finalize(self: *Self, allocator: std.mem.Allocator) !BRCMap {
            std.log.debug("Finalizing BRCBucketMap", .{});
            var finalMap: BRCMap = BRCMap.init(allocator);
            inline for (self.buckets) |bucket| finalMap.mergeWith(&bucket) catch @panic("merge failed");
            self.deinit();
            return finalMap;
        }
    };
}
