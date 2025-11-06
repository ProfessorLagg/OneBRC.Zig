const std = @import("std");
pub const Stat = @This();

sum: i48 = 0,
count: u32 = 0,
max: i16 = std.math.minInt(i16),
min: i16 = std.math.maxInt(i16),

pub fn init(val: i16) Stat {
    return Stat{
        .sum = val,
        .count = 1,
        .max = val,
        .min = val,
    };
}

/// Overrides the Stat with a single new entry
pub inline fn set(self: *Stat, val: i16) void {
    self.sum = val;
    self.count = 1;
    self.max = val;
    self.min = val;
}

pub fn meanF(self: *const Stat) f64 {
    const sumf: f64 = @floatFromInt(self.sum);
    const countf: f64 = @floatFromInt(self.count * 10);
    return sumf / countf;
}
pub fn minF(self: *const Stat) f64 {
    return @as(f64, @floatFromInt(self.min)) / 10.0;
}
pub fn maxF(self: *const Stat) f64 {
    return @as(f64, @floatFromInt(self.max)) / 10.0;
}

pub fn add(self: *Stat, val: i16) void {
    self.sum += @intCast(val);
    self.count += 1;
    self.max = @max(self.max, val);
    self.min = @min(self.min, val);
}

pub fn merge(a: *const Stat, b: *const Stat) Stat {
    return Stat{
        .sum = a.sum + b.sum,
        .count = a.count + b.count,
        .max = @max(a.max, b.max),
        .min = @min(a.min, b.min),
    };
}

pub fn mergeWith(self: *Stat, other: *const Stat) void {
    self.sum = self.sum + other.sum;
    self.count = self.count + other.count;
    self.max = @max(self.max, other.max);
    self.min = @min(self.min, other.min);
}
