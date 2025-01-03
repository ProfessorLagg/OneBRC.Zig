const std = @import("std");

const TypeError = error{NotNumber};

/// Function to compare type T
pub fn Comparison(comptime T: type) type {
    return (fn (T, T) CompareResult);
}

pub const CompareResult = enum(i8) { LessThan = -1, Equal = 0, GreaterThan = 1 };

/// Fast Branchless conversion.
/// lessThan must be a < b.
/// greaterThan must be a > b.
pub inline fn CompareFromBools(lessThan: bool, greaterThan: bool) CompareResult {
    const lt: i8 = @intFromBool(lessThan) * @as(i8, -1); // -1 if true, 0 if false
    const gt: i8 = @intFromBool(greaterThan); // 1 if true, 0 if false
    return @as(CompareResult, @enumFromInt(lt + gt));
}

// ===== NUMBERS ======

pub fn IsNumberType(T: type) bool {
    switch (@typeInfo(T)) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => {
            return true;
        },
        else => {
            return false;
        },
    }
}
/// Function to check if typeof v is a number
pub fn IsNumber(v: anytype) bool {
    return IsNumberType(@TypeOf(v));
}

/// Returns a numeric value comparison function for the input type
pub fn CompareNumberFn(comptime T: type) Comparison(T) {
    comptime {
        if (!IsNumberType(T)) {
            @compileError(@typeName(T) ++ " is not a number type!");
        }
    }
    return struct {
        pub fn comp(a: T, b: T) CompareResult {
            return CompareFromBools(a < b, a > b);
        }
    }.comp;
}

pub fn CompareNumber(a: anytype, b: anytype) CompareResult {
    comptime {
        const Ta = @TypeOf(a);
        const Tb = @TypeOf(b);
        if (Ta != Tb) {
            @compileError("a and b must be the same type, but a was " ++ @typeName(Ta) ++ ", and b was " ++ @typeName(Tb));
        }
    }
    const T: type = comptime @TypeOf(a);
    const compareFunc: Comparison(T) = comptime CompareNumberFn(T);
    return compareFunc(a, b);
}
