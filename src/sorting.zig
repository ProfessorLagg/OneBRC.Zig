const std = @import("std");

pub const CompareResult = enum(i8) {
    lt = -1,
    eq = 0,
    gt = 1,

    pub inline fn ge(cr: CompareResult) bool {
        return cr != .lt;
    }

    pub inline fn le(cr: CompareResult) bool {
        return cr != .gt;
    }
};

pub fn CompareFunction(comptime T: type) type {
    return fn (T, T) CompareResult;
}
pub fn CompareFunctionR(comptime T: type) type {
    return fn (*const T, *const T) CompareResult;
}

pub fn compareNumber(comptime T: type, a: T, b: T) CompareResult {
    // TODO comptime type checks
    const lt: i8 = @as(i8, @intFromBool(a < b)) * @as(i8, -1);
    const gt: i8 = @as(i8, @intFromBool(a > b));
    const ri: i8 = lt + gt;
    return @enumFromInt(ri);
}

pub fn compareStrings(a: []const u8, b: []const u8) CompareResult {
    const l: usize = @min(a.len, b.len);
    for (0..l) |i| {
        const cmp: CompareResult = @call(.always_inline, compareNumber, .{ u8, a[i], b[i] });
        if (cmp != .eq) return cmp;
    }
    return compareNumber(usize, a.len, b.len);
}

pub fn insertionSort(comptime T: type, comptime compare: CompareFunction(T), arr: []T) void {
    var i: isize = 1;
    while (i < arr.len) : (i += 1) {
        const iu: usize = @intCast(i);
        const key: T = arr[iu];
        var j: isize = i - 1;
        while (j >= 0 and compare(arr[@intCast(j)], key) == .gt) : (j -= 1) arr[@intCast(j + 1)] = arr[@intCast(j)];
        arr[@intCast(j + 1)] = key;
    }
}

pub fn insertionSortR(comptime T: type, comptime compare: CompareFunctionR(T), arr: []T) void {
    var i: isize = 1;
    while (i < arr.len) : (i += 1) {
        const iu: usize = @intCast(i);
        const key: T = arr[iu];
        var j: isize = i - 1;
        while (j >= 0 and compare(&arr[@intCast(j)], &key) == .gt) : (j -= 1) arr[@intCast(j + 1)] = arr[@intCast(j)];
        arr[@intCast(j + 1)] = key;
    }
}
