const builtin = @import("builtin");
const std = @import("std");

const TypeError = error{NotNumber};

/// Function to compare type T
pub fn Comparison(comptime T: type) type {
    return (fn (T, T) CompareResult);
}

pub fn ComparisonR(comptime T: type) type {
    return (fn (*const T, *const T) CompareResult);
}

pub const CompareResult = enum(i8) { LessThan = -1, Equal = 0, GreaterThan = 1 };

/// Fast Branchless conversion.
/// lessThan must be a < b.
/// greaterThan must be a > b.
pub inline fn compareFromBools(lessThan: bool, greaterThan: bool) CompareResult {
    const lt: i8 = @intFromBool(lessThan) * @as(i8, -1); // -1 if true, 0 if false
    const gt: i8 = @intFromBool(greaterThan); // 1 if true, 0 if false
    return @as(CompareResult, @enumFromInt(lt + gt));
}

// ===== NUMBERS ======
pub fn isUnsignedIntegerType(T: type) bool {
    const Ti = @typeInfo(T);
    return Ti == .Int and Ti.Int.signedness == .unsigned;
}
pub fn isSignedIntegerType(T: type) bool {
    const Ti = @typeInfo(T);
    return Ti == .Int and Ti.Int.signedness == .signed;
}
pub fn isIntegerType(T: type) bool {
    return @typeInfo(T) == .Int;
}
pub fn isNumberType(T: type) bool {
    const Ti: std.builtin.Type = @typeInfo(T);
    return switch (Ti) {
        .int, .float, .comptime_int, .comptime_float => true,
        else => false,
    };
}
/// true v @typeOf(v) is a number, else false
pub fn isNumber(v: anytype) bool {
    return isNumberType(@TypeOf(v));
}
/// Returns a numeric value comparison function for the input type
pub fn compareFloatFn(comptime T: type) Comparison(T) {
    comptime {
        const Ti: std.builtin.Type = @typeInfo(T);
        switch (Ti) {
            .float, .comptime_float => {},
            else => {
                @compileError(@typeName(T) ++ " is not a float type");
            },
        }
    }

    return struct {
        pub fn comp(a: T, b: T) CompareResult {
            const i = a - b;
            const r: i8 = @as(i8, @intFromBool(i > 0)) - @as(i8, @intFromBool(i < 0));
            return @enumFromInt(r);
        }
    }.comp;
}
/// Returns a numeric value comparison function for the input type
pub fn compareSignedFn(comptime T: type) Comparison(T) {
    comptime {
        const Ti: std.builtin.Type = @typeInfo(T);
        const err_msg = @typeName(T) ++ " is not a signed integer type";
        switch (Ti) {
            .comptime_int => {},
            .int => {
                if (Ti.int.signedness != .signed) @compileError(err_msg);
            },
            else => @compileError(err_msg),
        }
    }

    return struct {
        pub fn comp(a: T, b: T) CompareResult {
            const i = a - b;
            const r: i8 = @as(i8, @intFromBool(i > 0)) - @as(i8, @intFromBool(i < 0));
            return @enumFromInt(r);
        }
    }.comp;
}
/// Returns a numeric value comparison function for the input type
pub fn compareUnsignedFn(comptime T: type) Comparison(T) {
    comptime {
        const Tinfo: std.builtin.Type = @typeInfo(T);
        const err_msg = @typeName(T) ++ " is not an unsigned integer type";
        switch (Tinfo) {
            .comptime_int => {},
            .int => {
                if (Tinfo.int.signedness != .unsigned) {
                    @compileError(err_msg);
                }
            },
            else => {
                @compileError(err_msg);
            },
        }
    }

    return struct {
        pub fn comp(a: T, b: T) CompareResult {
            return compareFromBools(a < b, a > b);
        }
    }.comp;
}
/// Returns a numeric value comparison function for the input type
pub fn compareNumberFn(comptime T: type) Comparison(T) {
    comptime {
        if (!isNumberType(T)) {
            @compileError(@typeName(T) ++ " is not a number type");
        }
    }

    const Tinfo: std.builtin.Type = comptime @typeInfo(T);
    switch (Tinfo) {
        .float, .comptime_float => return compareFloatFn(T),
        .int => {
            if (Tinfo.int.signedness == .signed) {
                return compareSignedFn(T);
            } else {
                return compareUnsignedFn(T);
            }
        },
        .comptime_int => return compareSignedFn(T),
        else => unreachable,
    }
}

pub fn compareNumber(a: anytype, b: anytype) CompareResult {
    comptime {
        const Ta = @TypeOf(a);
        const Tb = @TypeOf(b);
        if (Ta != Tb) {
            @compileError("a and b must be the same type, but a was " ++ @typeName(Ta) ++ ", and b was " ++ @typeName(Tb));
        }
    }
    const T: type = comptime @TypeOf(a);
    const compareFunc: Comparison(T) = comptime compareNumberFn(T);
    return compareFunc(a, b);
}

fn CMPSB_REPNE(len: usize, a: *const u8, b: *const u8) u8 {
    // https://www.felixcloutier.com/x86/cmps:cmpsb:cmpsw:cmpsd:cmpsq
    // https://www.felixcloutier.com/x86/rep:repe:repz:repne:repnz
    // https://pdos.csail.mit.edu/6.828/2007/readings/i386/REP.htm
    // https://www.felixcloutier.com/x86/lahf
    return asm volatile ("REPE CMPSB\nLAHF"
        : [ret] "={AH}" (-> u8),
        : [len] "{RCX}" (len),
          [a] "{RSI}" (a),
          [b] "{RDI}" (b),
    );
}

// ===== STRINGS ======
pub inline fn indexOfFirstDifference(comptime T: type, a: []const u8, b: []const u8) ?T {
    const maxlen: comptime_int = comptime blk: {
        if (!isUnsignedIntegerType(T)) {
            @compileError("Expected unsigned integer type, but found " ++ @typeName(T));
        }
        break :blk std.math.maxInt(T);
    };
    std.debug.assert(a.len < @as(@TypeOf(a.len), maxlen));
    std.debug.assert(b.len < @as(@TypeOf(b.len), maxlen));

    const minLen: T = @min(a.len, b.len);
    const maxLen: T = @max(a.len, b.len);

    var i: T = 0;
    while (i < minLen) : (i += 1) {
        if (a[i] != b[i]) {
            return i;
        }
    }

    if (minLen == maxLen) {
        return null;
    } else {
        return minLen;
    }
}

// fn loadVector(comptime len: comptime_int, bytes: []const u8) @Vector(len, u8){
//     var vec: @Vector(len, u8) = undefined;

// }
// pub fn indexOfFirstDifferenceASM(a: []const u8, b: []const u8) u32 {
//     const veclen: comptime_int = comptime std.simd.suggestVectorLengthForCpu(u8, builtin.target);
//     const vec_a: [veclen]u8 = undefined;
//     const vec_b: [veclen]u8 = undefined;
//     @memcpy(vec_a[0..], a[0..]);
//     @memcpy(vec_b[0..], a[0..]);

//     return 0;
// }

pub inline fn compareString(a: []const u8, b: []const u8) CompareResult {
    var cmp: CompareResult = compareNumber(a.len, b.len);
    if (cmp != .Equal) {
        return cmp;
    }

    for (0..a.len) |i| {
        cmp = compareNumber(a[i], b[i]);
        if (cmp != .Equal) {
            return cmp;
        }
    }
    return .Equal;
}

pub fn compareStringR(a: *const []const u8, b: *const []const u8) CompareResult {
    return compareString(a.*, b.*);
}
