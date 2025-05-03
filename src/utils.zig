const builtin = @import("builtin");
const std = @import("std");

pub const mem = struct {
    pub const KB: comptime_int = 1024;
    pub const MB: comptime_int = KB * 1024;
    pub const GB: comptime_int = MB * 1024;
    /// Copy all of source into dest at position 0.
    /// dst.len must be >= src.len.
    /// If the slices overlap, dst.ptr must be <= src.ptr.
    pub fn copyForwards(comptime T: type, noalias dst: []T, noalias src: []const T) void {
        std.debug.assert(dst.len >= src.len);
        std.debug.assert(@intFromPtr(dst.ptr) <= @intFromPtr(src.ptr));
        for (dst[0..src.len], src) |*d, s| d.* = s;
    }

    fn copyBytes_generic(noalias dst: []u8, noalias src: []const u8) void {
        std.debug.assert(dst.len >= src.len);
        for (dst[0..src.len], src) |*d, s| d.* = s;
    }

    fn copyBytes_x86_64(noalias dst: []u8, noalias src: []const u8) void {
        comptime if (builtin.cpu.arch != .x86_64) @compileError("This function only works for x86_64 targets. You probably want copyBytes_generic");
        // https://www.felixcloutier.com/x86/rep:repe:repz:repne:repnz
        asm volatile ( // NO FOLD
            "rep movsb"
            :
            : [src] "{rsi}" (src.ptr),
              [dst] "{rdi}" (dst.ptr),
              [len] "{rcx}" (src.len),
        );
    }
    const copyBytes: @TypeOf(copyBytes_generic) = switch (builtin.cpu.arch) {
        .x86_64 => copyBytes_x86_64,
        else => copyBytes_generic,
    };
    /// Copies all of src into dst starting at index 0
    pub fn copy(comptime T: type, noalias dst: []T, noalias src: []const T) void {
        std.debug.assert(dst.len >= src.len);

        const dst_u8: []u8 = std.mem.sliceAsBytes(dst);
        const src_u8: []const u8 = std.mem.sliceAsBytes(src);
        copyBytes(dst_u8, src_u8);
    }
    pub fn clone(comptime T: type, allocator: std.mem.Allocator, a: []const T) ![]T {
        const result: []T = try allocator.alloc(T, a.len);
        copy(T, result, a);
        return result;
    }

    pub fn allocLargeBytes(allocator: std.mem.Allocator, n: usize) ![]u8 {
        const page_size: comptime_int = comptime std.heap.page_size_min;
        const Page: type = [page_size]u8;

        const page_count = try std.math.divCeil(usize, n, page_size);
        const pages: []Page = try allocator.alignedAlloc(Page, page_size, page_count);
        return std.mem.sliceAsBytes(pages);
    }

    pub fn readAllBytes(file: std.fs.File, allocator: std.mem.Allocator) ![]u8 {
        const stat = try file.stat();
        std.debug.assert(stat.size < std.math.maxInt(usize));
        const bytes: []u8 = try allocator.alloc(u8, stat.size);

        const bufsize: comptime_int = 2 * GB;
        if (bytes.len < bufsize) {
            _ = try file.read(bytes);
        } else {
            var slice: []u8 = bytes[0..];
            while (slice.len > 0) {
                const buf = slice[0..@min(slice.len, bufsize)];
                _ = try file.read(buf);
                slice = slice[buf.len..];
            }
        }

        return bytes;
    }

    pub fn initDefault(comptime T: type, comptime len: usize, default: T) [len]T {
        var result: [len]T = undefined;
        @memset(result[0..], default);
        return result;
    }
};

pub const types = struct {
    pub fn isPointerType(comptime T: type) bool {
        const Ti = comptime @typeInfo(T);
        return switch (Ti) {
            .pointer => true,
            else => false,
        };
    }
    pub fn isPointer(v: anytype) bool {
        const T = comptime @TypeOf(v);
        return isPointerType(T);
    }
    pub fn assertIsPointerType(comptime T: type) void {
        comptime if (!isPointerType(T)) @compileError("Expected pointer, but found: " ++ @typeName(T));
    }

    pub fn isNumberType(comptime T: type) bool {
        const Ti = comptime @typeInfo(T);
        return switch (Ti) {
            .int, .float, .comptime_float, .comptime_int => true,
            else => false,
        };
    }
    pub fn isNumber(v: anytype) bool {
        const T = comptime @TypeOf(v);
        return isNumberType(T);
    }
    pub fn assertIsNumberType(comptime T: type) void {
        comptime if (!isNumberType(T)) @compileError("Expected number, but found: " ++ @typeName(T));
    }

    pub fn isIntegerType(comptime T: type) bool {
        const Ti = @typeInfo(T);
        return Ti == .int;
    }
    pub fn isInteger(v: anytype) bool {
        const T = comptime @TypeOf(v);
        return isIntegerType(T);
    }
    pub fn assertIsIntegerType(comptime T: type) void {
        comptime if (!isIntegerType(T)) @compileError("Expected integer, but found: " ++ @typeName(T));
    }

    pub fn isUnsignedIntegerType(comptime T: type) bool {
        const Ti = @typeInfo(T);
        return Ti == .int and Ti.int.signedness == .unsigned;
    }
    pub fn isUnsignedInteger(v: anytype) bool {
        return isUnsignedIntegerType(@TypeOf(v));
    }
    pub fn assertIsUnsignedIntegerType(comptime T: type) void {
        comptime if (!isUnsignedIntegerType(T)) @compileError("Expected unsigned integer, but found: " ++ @typeName(T));
    }

    pub fn isSignedIntegerType(comptime T: type) bool {
        const Ti = @typeInfo(T);
        return Ti == .int and Ti.int.signedness == .signed;
    }
    pub fn isSignedInteger(v: anytype) bool {
        const T = comptime @TypeOf(v);
        return isSignedIntegerType(T);
    }
    pub fn assertIsSignedIntegerType(comptime T: type) void {
        comptime if (!isSignedIntegerType(T)) @compileError("Expected signed integer, but found: " ++ @typeName(T));
    }

    pub fn isFloatType(comptime T: type) bool {
        const Ti = @typeInfo(T);
        return Ti == .float;
    }
    pub fn isFloat(v: anytype) bool {
        const T = comptime @TypeOf(v);
        return isSignedIntegerType(T);
    }
    pub fn assertIsFloatType(comptime T: type) void {
        comptime if (!isFloatType(T)) @compileError("Expected floating point, but found: " ++ @typeName(T));
    }

    pub fn isVectorType(comptime T: type) bool {
        return @typeInfo(T) == .vector;
    }
    pub fn isVector(v: anytype) bool {
        const T: type = comptime @TypeOf(v);
        return isVectorType(T);
    }
    pub fn assertIsVectorType(comptime T: type) void {
        comptime if (!isVectorType(T)) @compileError("Expected vector, but found: " ++ @typeName(T));
    }

    pub fn isNumberVectorType(comptime T: type) bool {
        const Ti: std.builtin.Type = @typeInfo(T);
        if (Ti != .vector) return false;
        return isNumber(Ti.vector.child);
    }
    pub fn isNumberVector(v: anytype) bool {
        const T: type = @TypeOf(v);
        return isNumberType(T);
    }
    pub fn assertIsNumberVectorType(comptime T: type) void {
        comptime if (!isNumberVectorType(T)) @compileError("Expected vector of numbers, but found: " ++ @typeName(T));
    }

    pub fn isIntegerVectorType(comptime T: type) bool {
        const Ti: std.builtin.Type = @typeInfo(T);
        return Ti == .vector and isIntegerType(Ti.vector.child);
    }
    pub fn isIntegerVector(v: anytype) bool {
        const T: type = comptime @TypeOf(v);
        return isIntegerVectorType(T);
    }
    pub fn assertIsIntegerVectorType(comptime T: type) void {
        comptime if (!isIntegerVectorType(T)) @compileError("Expected integer vector, but found: " ++ @typeName(T));
    }

    pub fn isFloatVectorType(comptime T: type) bool {
        const Ti: std.builtin.Type = @typeInfo(T);
        return Ti == .vector and isFloatType(Ti.vector.child);
    }
    pub fn isFloatVector(v: anytype) bool {
        const T: type = comptime @TypeOf(v);
        return isFloatVectorType(T);
    }
    pub fn assertIsFloatVectorType(comptime T: type) void {
        comptime if (!isFloatVectorType(T)) @compileError("Expected vector of floats, but found: " ++ @typeName(T));
    }

    pub fn isNumberOrNumberVectorType(comptime T: type) bool {
        return isNumberType(T) or isNumberVectorType(T);
    }
    pub fn isNumberOrNumberVector(v: anytype) bool {
        const T: type = @TypeOf(v);
        return isNumberOrNumberVectorType(T);
    }
    pub fn assertIsNumberOrNumberVectorType(comptime T: type) void {
        comptime if (!isNumberOrNumberVector(T)) @compileError("Expected number or vector of numbers, but found: " ++ @typeName(T));
    }

    pub fn isFunctionType(comptime T: type) bool {
        const Ti: std.builtin.Type = @typeInfo(T);
        return Ti == .@"fn";
    }
    pub fn isFunction(v: anytype) bool {
        const T: type = @TypeOf(v);
        return isFunctionType(T);
    }
    pub fn assertIsFunctionType(comptime T: type) void {
        comptime if (!isFunctionType(T)) @compileError("Expected function, but found: " ++ @typeName(T));
    }

    pub fn isPrimitiveType(comptime T: type) bool {
        comptime {
            const primitiveTypes = [_]type{ i8, u8, i16, u16, i32, u32, i64, u64, i128, u128, isize, usize, c_char, c_short, c_ushort, c_int, c_uint, c_long, c_ulong, c_longlong, c_ulonglong, c_longdouble, f16, f32, f64, f80, f128, bool, anyopaque, void, noreturn, type, anyerror, comptime_int, comptime_float };
            for (primitiveTypes) |pT| {
                if (T == pT) return true;
            }
            return false;
        }
    }
    pub fn isPrimitive(v: anytype) bool {
        const T: type = @TypeOf(v);
        return isPrimitiveType(T);
    }
    pub fn assertIsPrimitiveType(comptime T: type) void {
        comptime if (!isPrimitiveType(T)) @compileError("Expected prmitive, but found: " ++ @typeName(T));
    }
};

pub const fs = struct {
    pub fn toAbsolutePath(allocator: std.mem.Allocator, p: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(p)) {
            return try mem.clone(u8, allocator, p);
        }

        const cwd = std.fs.cwd();
        const cwd_path = try cwd.realpathAlloc(allocator, ".");
        defer allocator.free(cwd_path);
        return try std.fs.path.resolve(allocator, &.{ cwd_path, p });
    }

    /// Opens a directory at the given path.
    /// The directory is a system resource that remains open until `close` is called on the result.
    /// Asserts that the path parameter is a utf8 or platform specific string
    /// Asserts that the path parameter has no null bytes.
    pub fn openDirAbsolute(absolute_path: []const u8, flags: std.fs.Dir.OpenOptions) !std.fs.Dir {
        const buffer_size: comptime_int = comptime (@as(comptime_int, std.fs.max_path_bytes) * @sizeOf(u3));
        var buffer_arr: [buffer_size]u8 = undefined;
        const buffer: []u8 = buffer_arr[0..];
        @memset(buffer, 0);
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        var arena = std.heap.ArenaAllocator.init(fba.allocator());
        defer arena.deinit();
        const allocator: std.mem.Allocator = arena.allocator();

        const validUtf8 = std.unicode.utf8ValidateSlice(absolute_path);
        const path: []const u8 = blk: {
            switch (builtin.target.os.tag) {
                .windows => {
                    const validWtf8 = std.unicode.wtf8ValidateSlice(absolute_path);
                    if (validWtf8) break :blk mem.clone(u8, allocator, absolute_path);
                    if (validUtf8) {
                        var view: std.unicode.Utf8View = try std.unicode.Utf8View.init(absolute_path);
                        var iter: std.unicode.Utf8Iterator = view.iter();
                        const buf: []u8 = allocator.alloc(u8, std.unicode.utf8CountCodepoints(absolute_path));
                        const slc: []u8 = buf[0..];
                        var len: usize = 0;
                        while (iter.nextCodepoint()) |cp| {
                            const encode_size = try std.unicode.wtf8Encode(cp, slc);
                            slc = slc[encode_size..];
                            len += encode_size;
                        }
                        break :blk buf[0..len];
                    }

                    @panic("could not convert path to wtf8");
                },
                .wasi => @panic("WiP"),
                else => break :blk try mem.clone(u8, allocator, absolute_path),
            }
        };

        return std.fs.openDirAbsolute(path, flags);
    }
};

pub const math = struct {
    /// Maps integers or vectors of integers from one range to another
    inline fn mapInt(comptime T: type, x: T, input_start: T, input_end: T, output_start: T, output_end: T) T {
        comptime if (!(types.isInt(T) or types.isIntegerVectorType(T))) @compileError("Expected integer or vector of integers, but found: " ++ @typeName(T));
        return (x - input_start) / (input_end - input_start) * (output_end - output_start) + output_start;
    }
    /// Maps floats or vectors of floats from one range to another
    inline fn mapFloat(comptime T: type, x: T, input_start: T, input_end: T, output_start: T, output_end: T) T {
        @setFloatMode(.optimized);
        comptime if (!(types.isFloatType(T) or types.isFloatVectorType(T))) @compileError("Expected float or vector of floats, but found: " ++ @typeName(T));
        const a = (x - input_start) / (input_end - input_start);
        const b = output_end - output_start;
        return @mulAdd(T, a, b, output_start);
    }
    /// Maps a number from one range to another range
    pub fn map(comptime T: type, x: T, input_start: T, input_end: T, output_start: T, output_end: T) T {
        const mapfn = comptime blk: {
            if (types.isIntegerType(T)) break :blk mapInt;
            if (types.isIntegerVectorType(T)) break :blk mapInt;
            if (types.isFloatType(T)) break :blk mapFloat;
            if (types.isFloatVectorType(T)) break :blk mapFloat;
            unreachable;
        };
        return @call(.always_inline, mapfn, .{ T, x, input_start, input_end, output_start, output_end });
    }

    pub fn fastIntParse(comptime T: type, numstr: []const u8) T {
        comptime types.assertIsSignedIntegerType(T);

        std.debug.assert(numstr.len > 0);
        const isNegative: bool = numstr[0] == '-';
        const isNegativeInt: T = @intFromBool(isNegative);

        var result: T = 0;
        var m: T = 1;

        var i: isize = @as(isize, @intCast(numstr.len)) - 1;
        while (i >= isNegativeInt) : (i -= 1) {
            const ci: T = @intCast(numstr[@as(usize, @bitCast(i))]);
            const valid: bool = ci >= 48 and ci <= 57;
            const validInt: T = @intFromBool(valid);
            const invalidInt: T = @intFromBool(!valid);
            result += validInt * ((ci - 48) * m); // '0' = 48
            m = (m * 10 * validInt) + (m * invalidInt);
        }

        const sign: T = (-1 * isNegativeInt) + @as(T, @intFromBool(!isNegative));
        return result * sign;
    }
    /// Checks if num is even without using %. Only works for unsigned integers
    pub fn isEven(comptime T: type, num: T) bool {
        comptime if (!types.isUnsignedIntegerType(T)) @compileError("Expected unsigned integer, but found " + @typeName(T));
        return (num & @as(T, 1)) == 0;
    }
    /// Checks if num is not even without using %. Only works for unsigned integers
    pub fn isUneven(comptime T: type, num: T) bool {
        comptime if (!types.isUnsignedIntegerType(T)) @compileError("Expected unsigned integer, but found " + @typeName(T));
        return (num & @as(T, 1)) == 1;
    }

    /// calculates numerator/denominator, rounding towards positive infinity.
    /// Only works on integers
    pub fn divCiel(comptime T: type, numerator: T, denominator: T) T {
        comptime {
            const isInt = types.isIntegerType(T);
            const isComptimeInt = T == comptime_int;
            if (!isInt and !isComptimeInt) @compileError("Expected integer or comptime_int, but found: " ++ @typeName(T));
        }
        const floor: T = @divFloor(numerator, denominator);
        const exactDivide = (floor * denominator) == numerator;
        return floor + @as(T, @intFromBool(!exactDivide));
    }
};
