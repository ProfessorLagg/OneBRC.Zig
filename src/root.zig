const builtin = @import("builtin");
const std = @import("std");

pub const c = @import("cImport.zig");

const fileMapping = @import("fileMapping.zig");
pub const MappedFile = fileMapping.MappedFile;
test fileMapping {
    _ = fileMapping;
}

const blockReaderNs = @import("BlockReader.zig");
pub const BlockReader = blockReaderNs.BlockReader;
test blockReaderNs {
    _ = blockReaderNs;
}

pub const Stat = @import("Stat.zig");
test Stat {
    _ = Stat;
}

const BRCMapNs = @import("BRCMap.zig");
pub const BRCMap = BRCMapNs.BRCMap;
pub const BRCMapUnmanaged = BRCMapNs.BRCMapUnmanaged;
test BRCMapNs {
    _ = BRCMapNs;
}

pub const sso = @import("sso.zig");
test sso {
    _ = sso;
}

pub const sorting = @import("sorting.zig");
test sorting {
    _ = sorting;
}

pub const benchmarking = @import("benchmarking.zig");
test benchmarking {
    _ = benchmarking;
}

pub const LineSplitter = @import("LineSplitter.zig");
test LineSplitter {
    const delimiter = '\n';
    const cities = @embedFile("cities.txt");
    var std_iter = std.mem.splitScalar(u8, cities, delimiter);
    var new_iter = LineSplitter{ .buffer = cities };
    var both_null: bool = false;
    while (!both_null) {
        const std_item = std_iter.next();
        const new_item = new_iter.next();
        std.testing.expectEqual(std_item, new_item) catch |err| {
            const std_str = if (std_item == null) "null"[0..] else std_item.?;
            const new_str = if (new_item == null) "null"[0..] else new_item.?;
            std.log.err("Expected \"{s}\", but found \"{s}\"", .{ std.fmt.fmtSliceEscapeLower(std_str), std.fmt.fmtSliceEscapeLower(new_str) });

            return err;
        };
        both_null = (std_item == null) and (new_item == null);
    }
}
pub fn brcIntParse(str: []const u8) i32 {
    const isNegative: bool = str[0] == '-';
    const isNegativeInt: i32 = @intFromBool(isNegative);
    const isPositiveInt: i32 = @intFromBool(!isNegative);
    const arr: []const u8 = str[@intFromBool(isNegative)..];
    return ((-1 * isNegativeInt) + isPositiveInt) * // sign
        (@as(i32, @intCast(arr[arr.len - 1] - '0')) + // 1s place
            @as(i32, @intCast(arr[arr.len - 3] - '0')) * 10 + // 10s place
            if (arr.len == 4) @as(i32, @intCast(arr[arr.len - 4] - '0')) * 100 else 0); // 100s place
}
test brcIntParse {
    const min: comptime_int = -999;
    const max: comptime_int = 999;

    var buf: [64]u8 = undefined;
    var i: i32 = min;
    @memset(buf[0..], 0);
    while (i <= max) : (i += 1) {
        const f: f128 = @as(f128, @floatFromInt(i)) / 10.0;
        const s = try std.fmt.bufPrint(buf[0..], "{d:.1}", .{f});
        const p = brcIntParse(s);
        std.testing.expectEqual(i, p) catch |e| {
            std.log.err("Parsed \"{s}\" wrong. Expected {d} but found {d}", .{ s, i, p });
            return e;
        };
    }
}

pub inline fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
    var list = std.ArrayList([]const T).init(allocator);
    defer list.deinit();
    var iter = std.mem.splitScalar(T, buffer, delimiter);
    while (iter.next()) |item| try list.append(item);
    return try list.toOwnedSlice();
}

const _asm = @import("_asm.zig");

pub fn eqlBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len <= 16) {
        if (a.len < 4) {
            const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
            return x == 0;
        }
        var x: u32 = 0;
        for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
        }
        return x == 0;
    }

    // Figure out the fastest way to scan through the input in chunks.
    // Uses vectors when supported and falls back to usize/words when not.
    const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size|
        struct {
            pub const size = vec_size;
            pub const Chunk = @Vector(size, u8);
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return @reduce(.Or, chunk_a != chunk_b);
            }
        }
    else
        struct {
            pub const size = @sizeOf(usize);
            pub const Chunk = usize;
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return chunk_a != chunk_b;
            }
        };

    inline for (1..6) |s| {
        const n = 16 << s;
        if (n <= Scan.size and a.len <= n) {
            const V = @Vector(n / 2, u8);
            var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
            x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
            const zero: V = @splat(0);
            return !@reduce(.Or, x != zero);
        }
    }
    // Compare inputs in chunks at a time (excluding the last chunk).
    for (0..(a.len - 1) / Scan.size) |i| {
        const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
        const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
        if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    // Compare the last chunk using an overlapping read (similar to the previous size strategies).
    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
}
test eqlBytes {
    const cities = @embedFile("cities.txt");
    const cityNames: [][]const u8 = try splitScalarToArray(u8, cities, '\n', std.testing.allocator);
    defer std.testing.allocator.free(cityNames);

    for (0..cityNames.len) |i| {
        const a: []const u8 = cityNames[i];
        for (i..cityNames.len) |j| {
            const b: []const u8 = cityNames[j];
            const expect: bool = std.mem.eql(u8, a, b);
            const found: bool = eqlBytes(a, b);
            std.testing.expectEqual(expect, found) catch |err| {
                std.log.err("eqlBytes failed at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
                return err;
            };
            // std.log.debug("eqlBytes succeeded at comparing \"{s}\" to \"{s}\". Expected {any} but found {any}", .{ a, b, expect, found });
        }
    }
}

/// Returns the number of cores, taking the current thread's cpu affinity into account
pub fn getAffinityCpuCount() usize {
    return @popCount(getCurrentProcessAffinity());
}

test getAffinityCpuCount {
    const cpuCount = try std.Thread.getCpuCount();
    const affinityCpuCount = getAffinityCpuCount();

    try std.testing.expectEqual(cpuCount, affinityCpuCount);
}

pub const getCurrentProcessAffinity = switch (builtin.target.os.tag) {
    .windows => getCurrentProcessAffinity_windows,
    .linux => getCurrentProcessAffinity_linux,
    else => @compileError("Not Implemented"),
};

fn getCurrentProcessAffinity_windows() c.DWORD64 {
    comptime if (builtin.target.os.tag != .windows) unreachable;

    var dwProcessAffinity: c.DWORD64 = undefined;
    var dwSystemAffinity: c.DWORD64 = undefined;
    _ = c.GetProcessAffinityMask(c.GetCurrentProcess(), &dwProcessAffinity, &dwSystemAffinity);
    return @intCast(dwProcessAffinity);
}

fn getCurrentProcessAffinity_linux() usize {
    comptime if (builtin.target.os.tag != .linux) unreachable;
    @compileError("WiP");
}

fn find_split_index_asm(line: []const u8) usize {
    @setRuntimeSafety(false);
    const left: usize = line.len - @min(line.len, 6);
    const r = asm volatile (
        \\add %rcx, %rsi # Add left to line.ptr
        \\mov (%rsi), %ebx # load 4 bytes from line[left] into ebx
        \\xor $0x000000003b3b3b3b, %ebx # XOR ebx with mask
        \\shr $8, %ebx # skip the 4th byte
        \\mov $2, %r8d 
        \\cmp $0, %bl 
        \\cmove %r8d, %eax # if %bl == 0 then set %eax = 2 
        \\shr $8, %ebx # go to the next byte
        \\mov $1, %r8d 
        \\cmp $0, %bl 
        \\cmove %r8d, %eax # if %bl == 0 then set %eax = 1
        \\xor %r9d , %r9d # set %r9d == 0
        \\cmp $0, %bh
        \\cmove %r9d, %eax # if %bh == 0 then set %eax = 0
        : [ret] "={eax}" (-> u32),
        : [p] "{rsi}" (line.ptr),
          [left] "{rcx}" (left),
        : "ebx", "r8d"
    );
    return r + left;
}

fn find_split_index_old(line: []const u8) usize {
    @setRuntimeSafety(false);
    const left: usize = line.len - @min(line.len, 6);
    return (@intFromBool(line[left] == ';') * left) + (@intFromBool(line[left + 1] == ';') * (left + 1)) + (@intFromBool(line[left + 2] == ';') * (left + 2));
}

fn find_split_index(line: []const u8) usize {
    @setRuntimeSafety(false);
    const left: usize = line.len - @min(line.len, 6);
    return left + @intFromBool(line[left + 1] == ';') + @as(usize, @intFromBool(line[left + 2] == ';')) * 2;
}

fn find_split_index2(line: []const u8) usize {
    @setRuntimeSafety(false);
    const left: usize = line.len - @min(line.len, 6);
    var r: usize = 0;
    var bytes_int: u32 = @as(*align(1) const u32, @ptrCast(&line[left])).*;
    bytes_int ^= 0x3b_3b_3b_3b;
    r += @as(u8, @truncate(bytes_int >> 1)) * 2;
    r += @as(u8, @truncate(bytes_int >> 2)) * 1;
    //r += @as(u8, @truncate(bytes_int >> 3)) * 0;
    return left + r;
}

test find_split_index {
    const _v0 = "9.9";
    const _v1 = "-9.9";
    const _v2 = "99.9";
    const _v3 = "-99.9";

    var line: [128]u8 = undefined;
    var i: usize = 1;
    while (i <= 100) : (i += 1) {
        const kstr = line[0..i];
        @memset(kstr, 'A');
        line[i] = ';';

        var vstr0 = line[i + 1 ..];
        vstr0.len = _v0.len;
        @memcpy(vstr0, _v0[0..]);
        var line0: []const u8 = line[0..];
        line0.len = kstr.len + 1 + vstr0.len;
        // std.debug.print("line0: \"{s}\"\n", .{line0});
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line0, ';'), find_split_index(line0));

        var vstr1 = line[i + 1 ..];
        vstr1.len = _v1.len;
        @memcpy(vstr1, _v1[0..]);
        var line1: []const u8 = line[0..];
        line1.len = kstr.len + 1 + vstr1.len;
        // std.debug.print("line1: \"{s}\"\n", .{line1});
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line1, ';'), find_split_index(line1));

        var vstr2 = line[i + 1 ..];
        vstr2.len = _v2.len;
        @memcpy(vstr2, _v2[0..]);
        var line2: []const u8 = line[0..];
        line2.len = kstr.len + 1 + vstr2.len;
        // std.debug.print("line2: \"{s}\"\n", .{line2});
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line2, ';'), find_split_index(line2));

        var vstr3 = line[i + 1 ..];
        vstr3.len = _v3.len;
        @memcpy(vstr3, _v3[0..]);
        var line3: []const u8 = line[0..];
        line3.len = kstr.len + 1 + vstr3.len;
        // std.debug.print("line3: \"{s}\"\n\n", .{line3});
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line3, ';'), find_split_index(line3));
    }
}
