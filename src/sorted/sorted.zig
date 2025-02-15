const std = @import("std");
const compare = @import("compare.zig");
const sortedArrayMap = @import("sortedArrayMap.zig");
pub usingnamespace compare;
pub usingnamespace sortedArrayMap;

test "SortedArrayMap.add" {
    const add_count: comptime_int = 99;
    const comparison: compare.ComparisonR(isize) = struct {
        fn cmp(a: *const isize, b: *const isize) compare.CompareResult {
            const cmpfn = comptime compare.compareNumberFn(isize);
            return cmpfn(a.*, b.*);
        }
    }.cmp;
    const MapType = sortedArrayMap.SortedArrayMap(isize, f32, comparison);

    var map = try MapType.init(std.testing.allocator);
    defer map.deinit();
    var success: bool = false;
    const start: isize = std.time.timestamp();
    for (0..add_count) |i| {
        const k: isize = start * @as(isize, @intCast(i + 1));
        const v: f32 = @as(f32, @floatFromInt(start)) / (@as(f32, @floatFromInt(start)) * @as(f32, @floatFromInt(i + 1)));
        success = map.add(&k, &v);
        if (!success) {
            std.log.err("could not add key '{d}' to map", .{k});
        }
        try std.testing.expect(success);
    }

    const fval: f32 = 123.456;
    success = map.add(&map.keys[0], &fval);
    try std.testing.expect(!success);
}

test "CompareNumber" {
    // Arrange
    const a_comptime_int: comptime_int = 3;
    const b_comptime_int: comptime_int = a_comptime_int * 2;
    const a_comptime_float: comptime_float = 3.0;
    const b_comptime_float: comptime_float = a_comptime_float * 2.0;

    const ai64: i64 = 3;
    const au64: u64 = @bitCast(ai64);
    const af64: f64 = @floatFromInt(ai64);
    const bi64: i64 = ai64 * 2;
    const bu64: u64 = @bitCast(bi64);
    const bf64: f64 = @floatFromInt(bi64);

    const ai32: i32 = 3;
    const au32: u32 = @bitCast(ai32);
    const af32: f32 = @floatFromInt(ai32);
    const bi32: i32 = ai32 * 2;
    const bu32: u32 = @bitCast(bi32);
    const bf32: f32 = @floatFromInt(bi32);

    const ai16: i16 = 3;
    const au16: u16 = @bitCast(ai16);
    const af16: f16 = @floatFromInt(ai16);
    const bi16: i16 = ai16 * 2;
    const bu16: u16 = @bitCast(bi16);
    const bf16: f16 = @floatFromInt(bi16);

    // Act
    const lt_comptime_int = compare.compareNumber(a_comptime_int, b_comptime_int);
    const eq_comptime_int = compare.compareNumber(a_comptime_int, a_comptime_int);
    const gt_comptime_int = compare.compareNumber(b_comptime_int, a_comptime_int);
    const lt_comptime_float = compare.compareNumber(a_comptime_float, b_comptime_float);
    const eq_comptime_float = compare.compareNumber(a_comptime_float, a_comptime_float);
    const gt_comptime_float = compare.compareNumber(b_comptime_float, a_comptime_float);
    const lti64 = compare.compareNumber(ai64, bi64);
    const ltu64 = compare.compareNumber(au64, bu64);
    const ltf64 = compare.compareNumber(af64, bf64);
    const eqi64 = compare.compareNumber(ai64, ai64);
    const equ64 = compare.compareNumber(au64, au64);
    const eqf64 = compare.compareNumber(af64, af64);
    const gti64 = compare.compareNumber(bi64, ai64);
    const gtu64 = compare.compareNumber(bu64, au64);
    const gtf64 = compare.compareNumber(bf64, af64);
    const lti32 = compare.compareNumber(ai32, bi32);
    const ltu32 = compare.compareNumber(au32, bu32);
    const ltf32 = compare.compareNumber(af32, bf32);
    const eqi32 = compare.compareNumber(ai32, ai32);
    const equ32 = compare.compareNumber(au32, au32);
    const eqf32 = compare.compareNumber(af32, af32);
    const gti32 = compare.compareNumber(bi32, ai32);
    const gtu32 = compare.compareNumber(bu32, au32);
    const gtf32 = compare.compareNumber(bf32, af32);
    const lti16 = compare.compareNumber(ai16, bi16);
    const ltu16 = compare.compareNumber(au16, bu16);
    const ltf16 = compare.compareNumber(af16, bf16);
    const eqi16 = compare.compareNumber(ai16, ai16);
    const equ16 = compare.compareNumber(au16, au16);
    const eqf16 = compare.compareNumber(af16, af16);
    const gti16 = compare.compareNumber(bi16, ai16);
    const gtu16 = compare.compareNumber(bu16, au16);
    const gtf16 = compare.compareNumber(bf16, af16);

    // Assert
    try std.testing.expectEqual(.LessThan, lt_comptime_int);
    try std.testing.expectEqual(.Equal, eq_comptime_int);
    try std.testing.expectEqual(.GreaterThan, gt_comptime_int);

    try std.testing.expectEqual(.LessThan, lt_comptime_float);
    try std.testing.expectEqual(.Equal, eq_comptime_float);
    try std.testing.expectEqual(.GreaterThan, gt_comptime_float);

    try std.testing.expectEqual(.LessThan, lti64);
    try std.testing.expectEqual(.LessThan, ltu64);
    try std.testing.expectEqual(.LessThan, ltf64);
    try std.testing.expectEqual(.Equal, eqi64);
    try std.testing.expectEqual(.Equal, equ64);
    try std.testing.expectEqual(.Equal, eqf64);
    try std.testing.expectEqual(.GreaterThan, gti64);
    try std.testing.expectEqual(.GreaterThan, gtu64);
    try std.testing.expectEqual(.GreaterThan, gtf64);

    try std.testing.expectEqual(.LessThan, lti32);
    try std.testing.expectEqual(.LessThan, ltu32);
    try std.testing.expectEqual(.LessThan, ltf32);
    try std.testing.expectEqual(.Equal, eqi32);
    try std.testing.expectEqual(.Equal, equ32);
    try std.testing.expectEqual(.Equal, eqf32);
    try std.testing.expectEqual(.GreaterThan, gti32);
    try std.testing.expectEqual(.GreaterThan, gtu32);
    try std.testing.expectEqual(.GreaterThan, gtf32);

    try std.testing.expectEqual(.LessThan, lti16);
    try std.testing.expectEqual(.LessThan, ltu16);
    try std.testing.expectEqual(.LessThan, ltf16);
    try std.testing.expectEqual(.Equal, eqi16);
    try std.testing.expectEqual(.Equal, equ16);
    try std.testing.expectEqual(.Equal, eqf16);
    try std.testing.expectEqual(.GreaterThan, gti16);
    try std.testing.expectEqual(.GreaterThan, gtu16);
    try std.testing.expectEqual(.GreaterThan, gtf16);
} 
