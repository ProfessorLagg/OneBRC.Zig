const builtin = @import("builtin");
const std = @import("std");

fn Vecstr(comptime L: comptime_int) type {
    comptime {
        if (!std.math.isPowerOfTwo(L)) @compileError("Vecstr len must be a power of two");
        if (L < 8) @compileError("Vecstr len must be >8");
    }

    return struct {
        const Self = @This();
        data: @Vector(L, u8) = @splat(0),
        pub inline fn create(v: []const u8) Self {
            var r: Self = undefined;
            r.set(v);
            return r;
        }
        pub fn set(self: *Self, v: []const u8) void {
            std.debug.assert(v.len <= L);
            var arr: [L]u8 = undefined;
            @memset(arr[0..], 0);
            @memcpy(arr[0..v.len], v);
            self.data = @bitCast(arr);
        }
        pub fn asSlice(self: *const Self) []const u8 {
            const l = self.length();
            const ptr: [*]const u8 = @ptrCast(&self.data);
            return ptr[0..l];
        }
        pub fn length(self: *const Self) usize {
            const veq0 = self.data == @as(@Vector(L, u8), @splat(0));
            return std.simd.firstTrue(veq0) orelse L;
        }
        pub fn compare(a: *const Self, b: *const Self) i8 {
            const lt: @Vector(L, i8) = @intFromBool(a.data < b.data);
            const gt: @Vector(L, i8) = @intFromBool(a.data > b.data);
            const cp: @Vector(L, i8) = lt - gt;
            const cpne0: @Vector(L, bool) = cp != @as(@Vector(L, i8), @splat(0));
            if (std.simd.firstTrue(cpne0)) |i| return cp[i];
            return 0;
        }
        pub fn sum(self: *const Self) usize {
            const vu16: @Vector(L, u16) = self.data;
            return @reduce(.Add, vu16);
        }

        test set {
            const str = "ABCDEFGH";
            const vec: Self = Self.create(str[0..]);
            try std.testing.expectEqualStrings(str, vec.asSlice());
        }

        test compare {
            const strA = "ABCDEFGH";
            const strB = "12345678";
            const vecA: Self = Self.create(strA[0..]);
            const vecB: Self = Self.create(strB[0..]);

            const AcmpB = Self.compare(&vecA, &vecB);
            const AcmpA = Self.compare(&vecA, &vecA);
            const BcmpA = Self.compare(&vecB, &vecA);
            const BcmpB = Self.compare(&vecB, &vecB);

            try std.testing.expectEqual(-1, AcmpB);
            try std.testing.expectEqual(0, AcmpA);
            try std.testing.expectEqual(1, BcmpA);
            try std.testing.expectEqual(0, BcmpB);
        }

        test sum {
            var str: [L]u8 = undefined;
            @memset(str[0..], 'z');
            const vec: Self = Self.create(str[0..]);
            const str_sum: usize = @import("utils.zig").math.sumBytes(str[0..]);
            const vec_sum: usize = vec.sum();

            try std.testing.expectEqual(str_sum, vec_sum);
        }
    };
}
pub const Vecstr8 = Vecstr(8);
pub const Vecstr16 = Vecstr(16);
pub const Vecstr32 = Vecstr(32);
pub const Vecstr64 = Vecstr(64);
pub const Vecstr128 = Vecstr(128);
test Vecstr8 {
    _ = Vecstr8;
}
test Vecstr16 {
    _ = Vecstr16;
}
test Vecstr32 {
    _ = Vecstr32;
}
test Vecstr64 {
    _ = Vecstr64;
}
test Vecstr128 {
    _ = Vecstr128;
}
