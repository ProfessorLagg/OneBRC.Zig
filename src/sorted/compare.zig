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
pub fn isNumberType(T: type) bool {
    switch (@typeInfo(T)) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => {
            return true;
        },
        else => {
            return false;
        },
    }
}
/// true v @typeOf(v) is a number, else false
pub fn isNumber(v: anytype) bool {
    return isNumberType(@TypeOf(v));
}
/// Returns a numeric value comparison function for the input type
pub fn compareFloatFn(comptime T: type) Comparison(T) {
    comptime {
        switch (@typeInfo(T)) {
            .Float, .ComptimeFloat => {},
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
        const Tinfo: std.builtin.Type = @typeInfo(T);
        const err_msg = @typeName(T) ++ " is not a signed integer type";
        switch (Tinfo) {
            .ComptimeInt => {},
            .Int => {
                if (Tinfo.Int.signedness != .signed) {
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
            .ComptimeInt => {},
            .Int => {
                if (Tinfo.Int.signedness != .unsigned) {
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
        .Float, .ComptimeFloat => return compareFloatFn(T),
        .Int => {
            if (Tinfo.Int.signedness == .signed) {
                return compareSignedFn(T);
            } else {
                return compareUnsignedFn(T);
            }
        },
        .ComptimeInt => return compareSignedFn(T),
        else => unreachable,
    }
}
/// Compares 2 numbers of the same type
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
