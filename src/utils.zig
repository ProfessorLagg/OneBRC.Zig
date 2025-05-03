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
};

pub const types = struct {
    pub fn isPrimitive(comptime T: type) bool {
        comptime {
            const primitiveTypes = [_]type{ i8, u8, i16, u16, i32, u32, i64, u64, i128, u128, isize, usize, c_char, c_short, c_ushort, c_int, c_uint, c_long, c_ulong, c_longlong, c_ulonglong, c_longdouble, f16, f32, f64, f80, f128, bool, anyopaque, void, noreturn, type, anyerror, comptime_int, comptime_float };
            for (primitiveTypes) |pT| {
                if (T == pT) return true;
            }
            return false;
        }
    }

    pub fn isInt(comptime T: type) bool {
        comptime {
            const Ti: std.builtin.Type = @typeInfo(T);
            return Ti == .int;
        }
    }

    pub fn isUnsignedInt(comptime T: type) bool {
        comptime {
            const Ti: std.builtin.Type = @typeInfo(T);
            if (Ti != .int) return false;
            return Ti.int.signedness == .unsigned;
        }
    }

    pub fn isSignedInt(comptime T: type) bool {
        comptime {
            const Ti: std.builtin.Type = @typeInfo(T);
            if (Ti != .int) return false;
            return Ti.int.signedness == .unsigned;
        }
    }
};

pub const args = struct {
    pub fn readArgsAlloc(allocator: std.mem.Allocator) ![][]u8 {
        const args_iter: std.process.ArgIterator = try std.process.argsWithAllocator(allocator);
        defer args_iter.deinit();

        const args_list: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(allocator);
        while (args_iter.next()) |a| {
            try args_list.append(a[0..]);
        }

        return try args_list.toOwnedSlice();
    }

    pub const ArgDef = struct {
        name: @Type(.enum_literal),
        optional: bool,
        valuetype: ?type = null,
    };
    pub const ArgSet = struct {
        definitions: []const ArgDef,
        pub fn init(set: []const ArgDef) ArgSet {
            return ArgSet{
                .definitions = set,
            };
        }


    };
};
