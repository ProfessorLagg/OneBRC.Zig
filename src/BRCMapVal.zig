const std = @import("std");

pub const MapVal = @This();
pub const FinalMapVal = struct {
    mean: f64 = 0,
    min: f64 = 0,
    max: f64 = 0,
};
pub const None: MapVal = .{};

sum: i64 = 0,
count: u32 = 0,
min: i16 = std.math.maxInt(i16),
max: i16 = std.math.minInt(i16),
pub inline fn add(self: *MapVal, v: i64) void {
    @setRuntimeSafety(false);
    self.sum += v;
    self.count += 1;
    const v16: i16 = @intCast(v);
    self.min = @min(self.min, v16);
    self.max = @max(self.max, v16);
}
pub inline fn merge(self: *MapVal, other: *const MapVal) void {
    @setRuntimeSafety(false);
    self.sum += other.sum;
    self.count += other.count;
    self.min = @min(self.min, other.min);
    self.max = @max(self.max, other.max);
}
pub inline fn finalize(self: *const MapVal) FinalMapVal {
    @setRuntimeSafety(false);
    @setFloatMode(.optimized);
    const sum_f: f64 = @floatFromInt(self.sum);
    const count_f: f64 = @floatFromInt(self.count);
    const min_f: f64 = @floatFromInt(self.min);
    const max_f: f64 = @floatFromInt(self.max);
    return .{
        .mean = sum_f / (count_f * 10.0),
        .min = min_f / 10.0,
        .max = max_f / 10.0,
    };
}
pub inline fn create(v: i64) MapVal {
    std.debug.assert(v >= -999);
    std.debug.assert(v <= 999);

    const v16: i16 = @intCast(v);
    return .{
        .sum = v,
        .count = 1,
        .min = v16,
        .max = v16,
    };
}
