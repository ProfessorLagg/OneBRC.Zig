const builtin = @import("builtin");
const std = @import("std");

pub const debug = @import("debug.zig");
test debug {
    _ = debug;
}

pub const SpinningMutex = @import("SpinningMutex.zig");
pub const Mutex = SpinningMutex;

pub const c = @import("cImport.zig").c;
pub const intrinsics = @import("intrinsics.zig");

const fileMapping = @import("fileMapping.zig");
pub const MappedFile = fileMapping.MappedFile;
test fileMapping {
    _ = fileMapping;
}

const blockReaderNs = @import("BlockReader.zig");
pub const MappedFileBlockReader = blockReaderNs.MappedFileBlockReader;
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
            std.log.err("Expected \"{any}\", but found \"{any}\"", .{ std.ascii.hexEscape(std_str, std.fmt.Case.lower), std.ascii.hexEscape(new_str, std.fmt.Case.lower) });

            return err;
        };
        both_null = (std_item == null) and (new_item == null);
    }
}

pub inline fn splitScalarToArray(comptime T: type, buffer: []const T, delimiter: T, allocator: std.mem.Allocator) ![][]const T {
    var list = std.ArrayList([]const T){};
    defer list.deinit(allocator);
    var iter = std.mem.splitScalar(T, buffer, delimiter);
    while (iter.next()) |item| try list.append(allocator, item);
    return try list.toOwnedSlice(allocator);
}

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
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line0, ';'), find_split_index(line0));

        var vstr1 = line[i + 1 ..];
        vstr1.len = _v1.len;
        @memcpy(vstr1, _v1[0..]);
        var line1: []const u8 = line[0..];
        line1.len = kstr.len + 1 + vstr1.len;
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line1, ';'), find_split_index(line1));

        var vstr2 = line[i + 1 ..];
        vstr2.len = _v2.len;
        @memcpy(vstr2, _v2[0..]);
        var line2: []const u8 = line[0..];
        line2.len = kstr.len + 1 + vstr2.len;
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line2, ';'), find_split_index(line2));

        var vstr3 = line[i + 1 ..];
        vstr3.len = _v3.len;
        @memcpy(vstr3, _v3[0..]);
        var line3: []const u8 = line[0..];
        line3.len = kstr.len + 1 + vstr3.len;
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, line3, ';'), find_split_index(line3));
    }
}

pub const windows = struct {
    pub fn GetCurrentProcessToken() !c.HANDLE {
        var result: c.HANDLE = null;
        if (c.OpenProcessToken(c.GetCurrentProcess(), c.TOKEN_ADJUST_PRIVILEGES, &result) == 0) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
        return result;
    }
    pub fn SetPrivilege(hToken: c.HANDLE, lpszPrivilege: c.LPCSTR, enable: bool) !void {
        var luid: c.LUID = undefined;
        var tp: c.TOKEN_PRIVILEGES = .{};

        if (c.LookupPrivilegeValueA(null, lpszPrivilege, &luid) == 0) return std.os.windows.unexpectedError(std.os.windows.GetLastError());

        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = if (enable) c.SE_PRIVILEGE_ENABLED else 0;

        if (c.AdjustTokenPrivileges(hToken, 1, &tp, @sizeOf(c.TOKEN_PRIVILEGES), null, null) == 0) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    }
    pub fn SetPrivilegeCurrentProcess(lpszPrivilege: c.LPCSTR, enable: bool) !void {
        const hToken: c.HANDLE = try GetCurrentProcessToken();
        defer _ = c.CloseHandle(hToken);
        return SetPrivilege(hToken, lpszPrivilege, enable);
    }

    pub fn disable_file_cache() !void {
        comptime {
            if (builtin.target.os.tag != .windows) @compileError("This only works on windows");
        }
        try SetPrivilegeCurrentProcess(c.SE_INCREASE_QUOTA_NAME, true);
        if (c.SetSystemFileCacheSize(0, 0, c.FILE_CACHE_MAX_HARD_ENABLE | c.FILE_CACHE_MIN_HARD_ENABLE) == 0) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    }
};

var stderr_lock: Mutex = .{};
var stderr_buffer: [4096]u8 = undefined;
var stderr_file: ?std.fs.File = null;
var stderr_writer: ?std.fs.File.Writer = null;
pub fn getStderr() *std.io.Writer {
    if (stderr_file == null) stderr_file = std.fs.File.stderr();
    if (stderr_writer == null) stderr_writer = stderr_file.?.writer(stderr_buffer[0..]);
    return &stderr_writer.?.interface;
}
pub fn stderrPrintEx(comptime fmt: []const u8, args: anytype, comptime flush: bool) void {
    stderr_lock.lock();
    defer stderr_lock.unlock();
    const stderr = getStderr();
    stderr.print(fmt, args) catch @panic("Printing failed");
    if (flush) {
        stderr.flush() catch @panic("Flushing stderr failed");
    }
}
pub fn stderrPrint(comptime fmt: []const u8, args: anytype) void {
    stderrPrintEx(fmt, args, true);
}
pub fn stderrPrintln(comptime fmt: []const u8, args: anytype) void {
    stderrPrint(fmt ++ "\n", args);
}

var stdout_lock: Mutex = .{};
var stdout_buffer: [4096]u8 = undefined;
var stdout_file: ?std.Io.File = null;
var stdout_writer: ?std.Io.File.Writer = null;
pub fn getStdout() *std.Io.Writer {
    if (stdout_file == null) stdout_file = std.Io.File.stdout();
    if (stdout_writer == null) stdout_writer = stdout_file.?.writer(stdout_buffer[0..]);
    return &stdout_writer.?.interface;
}
pub fn stdoutPrint(comptime fmt: []const u8, args: anytype) void {
    stdout_lock.lock();
    defer stdout_lock.unlock();
    const stdout = getStdout();
    stdout.print(fmt, args) catch @panic("Printing failed");
    stdout.flush() catch @panic("Flushing stdout failed");
}
pub fn stdoutPrintln(comptime fmt: []const u8, args: anytype) void {
    stdoutPrint(fmt ++ "\n", args);
}
pub fn clone(comptime T: type, allocator: std.mem.Allocator, items: []const T) ![]T {
    const result: []T = try allocator.alloc(T, items.len);
    @memcpy(result, items);
    return result;
}

pub fn printMemoryStats(comptime T: type, writer: *std.io.Writer) !void {
    try writer.print("memory stats for {s}: size = {d}, alignment = {d}\n", .{ @typeName(T), @sizeOf(T), @alignOf(T) });
    const Ti: std.builtin.Type = @typeInfo(T);
    if (Ti == .pointer) try printMemoryStats(Ti.pointer.child, writer);
}

pub fn lastIndexOfScalar2(slice: []const u8, comptime value: u8) ?usize {
    @setRuntimeSafety(false);
    const vlen: comptime_int = comptime std.simd.suggestVectorLength(u8) orelse unreachable;

    var i: usize = slice.len;
    while (i != 0) {
        i -= 1;
        if (slice[i] == value) return i;
        if (@intFromPtr(&slice[i]) % vlen == 0) break;
    }

    const vidx: @Vector(vlen, u8) = comptime std.simd.iota(u8, vlen);
    const vfnd: @Vector(vlen, u8) = comptime @splat(value);
    while (i >= vlen) {
        i -= vlen;
        const veq = @as(*const @Vector(vlen, u8), @ptrFromInt(@intFromPtr(&slice[i]))).* == vfnd;
        const vi = @reduce(.Max, vidx * @as(@Vector(vlen, u8), @intFromBool(veq)));
        if (vi > 0 or veq[0]) return @as(usize, vi) + i;
    }

    while (i != 0) {
        i -= 1;
        if (slice[i] == value) return i;
    }
    return null;
}

test lastIndexOfScalar2 {
    const len: comptime_int = 65356;
    const bytes: []u8 = try std.testing.allocator.alloc(u8, len);
    defer std.testing.allocator.free(bytes[0..]);
    var prng = std.Random.DefaultPrng.init(2025_10_12);
    prng.fill(bytes[0..]);

    inline for (0..0xFF) |b| {
        const exp = std.mem.lastIndexOfScalar(u8, bytes[0..], b);
        const fnd = lastIndexOfScalar2(bytes[0..], b);
        try std.testing.expectEqual(exp, fnd);
    }
}

pub fn lastIndexOfScalar3(slice: []const u8, comptime value: u8) ?usize {
    @setRuntimeSafety(false);
    const vlen: comptime_int = comptime std.simd.suggestVectorLength(u8) orelse unreachable;

    var i: usize = slice.len;
    const vidx: @Vector(vlen, u8) = comptime std.simd.iota(u8, vlen);
    const vfnd: @Vector(vlen, u8) = comptime @splat(value);
    while (i >= vlen) {
        i -= vlen;
        const veq = @as(*const @Vector(vlen, u8), @ptrFromInt(@intFromPtr(&slice[i]))).* == vfnd;
        const vi = @reduce(.Max, vidx * @as(@Vector(vlen, u8), @intFromBool(veq)));
        if (vi > 0 or veq[0]) return @as(usize, vi) + i;
    }

    while (i != 0) {
        i -= 1;
        if (slice[i] == value) return i;
    }
    return null;
}

test lastIndexOfScalar3 {
    const len: comptime_int = 65356;
    const bytes: []u8 = try std.testing.allocator.alloc(u8, len);
    defer std.testing.allocator.free(bytes[0..]);
    var prng = std.Random.DefaultPrng.init(2025_10_12);
    prng.fill(bytes[0..]);

    inline for (0..0xFF) |b| {
        const exp = std.mem.lastIndexOfScalar(u8, bytes[0..], b);
        const fnd = lastIndexOfScalar3(bytes[0..], b);
        try std.testing.expectEqual(exp, fnd);
    }
}

pub inline fn sumLen(comptime T: type, slices: []const []const T) usize {
    var r: usize = 0;
    for (slices) |slice| r += slice.len;
    return r;
}

pub const Args2 = struct {
    pub const Argument: type = []const u8;
    exe: []const u8,
    args: []const Argument,

    inline fn dupeArg(arg: [:0]const u8, gpa: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const maxlen = arg.len + @sizeOf(u8);
        const slice = @as([*]const u8, @ptrCast(&arg[0]))[0..maxlen];

        const len = std.mem.findScalarLast(u8, slice, 0) orelse return &.{};
        return try gpa.dupe(u8, slice[0..len]);
    }

    pub fn init(args: std.process.Args, gpa: std.mem.Allocator) !@This() {
        var iter = try args.iterateAllocator(gpa);
        defer iter.deinit();

        const first: [:0]const u8 = iter.next() orelse unreachable;
        const exe = try dupeArg(first, gpa);

        var list: std.ArrayList([]const u8) = .empty;
        defer list.deinit(gpa);
        while (iter.next()) |a| {
            const da = try dupeArg(a, gpa);
            try list.append(gpa, da);
        }

        return .{
            .exe = exe,
            .args = if (list.items.len > 0) try list.toOwnedSlice(gpa) else &.{},
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        gpa.free(self.exe);
        for (self.args) |a| gpa.free(a);
        gpa.free(self.args);
        self.args = &.{};
    }
};

pub fn GenericTimer(comptime Timestamp: type, comptime now: fn () Timestamp) type {
    return struct {
        const Duration: type = Timestamp;
        startTime: Timestamp,
        pub inline fn start() @This() {
            var rsp: @This() = undefined;
            rsp.reset();
            return rsp;
        }
        pub inline fn reset(self: *@This()) void {
            self.startTime = @call(.always_inline, now, .{});
        }
        pub inline fn read(self: *const @This()) Duration {
            const endTime: Timestamp = @call(.always_inline, now, .{});
            return endTime - self.startTime;
        }
    };
}

pub fn TimestampFn(comptime clock: std.Io.Clock) fn () i96 {
    return struct {
        fn nowWindows() std.Io.Timestamp {
            switch (clock) {
                .real => {
                    // RtlGetSystemTimePrecise() has a granularity of 100 nanoseconds
                    // and uses the NTFS/Windows epoch, which is 1601-01-01.
                    const epoch_ns = std.time.epoch.windows * std.time.ns_per_s;
                    return .{ .nanoseconds = @as(i96, std.os.windows.ntdll.RtlGetSystemTimePrecise()) * 100 + epoch_ns };
                },
                .awake, .boot => {
                    // We don't need to cache QPF as it's internally just a memory read to KUSER_SHARED_DATA
                    // (a read-only page of info updated and mapped by the kernel to all processes):
                    // https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/ns-ntddk-kuser_shared_data
                    // https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntexapi_x/kuser_shared_data/index.htm
                    const qpf: u64 = qpf: {
                        var qpf: std.os.windows.LARGE_INTEGER = undefined;
                        std.debug.assert(std.os.windows.ntdll.RtlQueryPerformanceFrequency(&qpf).toBool());
                        break :qpf @bitCast(qpf);
                    };

                    // QPC on windows doesn't fail on >= XP/2000 and includes time suspended.
                    const qpc: u64 = qpc: {
                        var qpc: std.os.windows.LARGE_INTEGER = undefined;
                        std.debug.assert(std.os.windows.ntdll.RtlQueryPerformanceCounter(&qpc).toBool());
                        break :qpc @bitCast(qpc);
                    };

                    // 10Mhz (1 qpc tick every 100ns) is a common enough QPF value that we can optimize on it.
                    // https://github.com/microsoft/STL/blob/785143a0c73f030238ef618890fd4d6ae2b3a3a0/stl/inc/chrono#L694-L701
                    const common_qpf = 10_000_000;
                    if (qpf == common_qpf) return .{ .nanoseconds = qpc * (std.time.ns_per_s / common_qpf) };

                    // Convert to ns using fixed point.
                    const scale = @as(u64, std.time.ns_per_s << 32) / @as(u32, @intCast(qpf));
                    const result = (@as(u96, qpc) * scale) >> 32;
                    return .{ .nanoseconds = @intCast(result) };
                },
                .cpu_process => {
                    const handle = std.os.windows.GetCurrentProcess();
                    var times: std.os.windows.KERNEL_USER_TIMES = undefined;

                    // https://github.com/reactos/reactos/blob/master/ntoskrnl/ps/query.c#L442-L485
                    if (std.os.windows.ntdll.NtQueryInformationProcess(
                        handle,
                        .Times,
                        &times,
                        @sizeOf(std.os.windows.KERNEL_USER_TIMES),
                        null,
                    ) != .SUCCESS) return .zero;

                    const sum = @as(i96, times.UserTime) + @as(i96, times.KernelTime);
                    return .{ .nanoseconds = sum * 100 };
                },
                .cpu_thread => {
                    const handle = std.os.windows.GetCurrentThread();
                    var times: std.os.windows.KERNEL_USER_TIMES = undefined;

                    // https://github.com/reactos/reactos/blob/master/ntoskrnl/ps/query.c#L2971-L3019
                    if (std.os.windows.ntdll.NtQueryInformationThread(
                        handle,
                        .Times,
                        &times,
                        @sizeOf(std.os.windows.KERNEL_USER_TIMES),
                        null,
                    ) != .SUCCESS) return .zero;

                    const sum = @as(i96, times.UserTime) + @as(i96, times.KernelTime);
                    return .{ .nanoseconds = sum * 100 };
                },
            }
        }
        fn nowWasi() std.Io.Timestamp {
            var ns: std.os.wasi.timestamp_t = undefined;
            const wasi_clock = switch (clock) {
                .real => .REALTIME,
                .awake => .MONOTONIC,
                .boot => .MONOTONIC,
                .cpu_process => .PROCESS_CPUTIME_ID,
                .cpu_thread => .THREAD_CPUTIME_ID,
            };
            const err = std.os.wasi.clock_time_get(wasi_clock, 1, &ns);
            if (err != .SUCCESS) return .zero;
            return .fromNanoseconds(ns);
        }
        fn nowPosix() std.Io.Timestamp {
            const clock_id: std.posix.clockid_t = switch (clock) {
                .real => std.posix.CLOCK.REALTIME,
                .awake => switch (builtin.os.tag) {
                    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => std.posix.CLOCK.UPTIME_RAW,
                    else => std.posix.CLOCK.MONOTONIC,
                },
                .boot => switch (builtin.os.tag) {
                    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => std.posix.CLOCK.MONOTONIC_RAW,
                    // On freebsd derivatives, use MONOTONIC_FAST as currently there's
                    // no precision tradeoff.
                    .freebsd, .dragonfly => std.posix.CLOCK.MONOTONIC_FAST,
                    // On linux, use BOOTTIME instead of MONOTONIC as it ticks while
                    // suspended.
                    .linux => std.posix.CLOCK.BOOTTIME,
                    // On other posix systems, MONOTONIC is generally the fastest and
                    // ticks while suspended.
                    else => std.posix.CLOCK.MONOTONIC,
                },
                .cpu_process => std.posix.CLOCK.PROCESS_CPUTIME_ID,
                .cpu_thread => std.posix.CLOCK.THREAD_CPUTIME_ID,
            };
            var timespec: std.posix.timespec = undefined;
            switch (std.posix.errno(std.posix.system.clock_gettime(clock_id, &timespec))) {
                .SUCCESS => return .{ .nanoseconds = @intCast(@as(i128, timespec.sec) * std.time.ns_per_s + timespec.nsec) },
                else => return .zero,
            }
        }
        fn f() i96 {
            const timestamp = switch (builtin.os.tag) {
                .windows => nowWindows,
                .wasi => nowWasi,
                else => nowPosix,
            }();
            return timestamp.nanoseconds;
        }
    }.f;
}

pub const Timer_rdtsc = GenericTimer(u64, intrinsics.rdtsc, @as(0, u64));
pub const Timer_awake = GenericTimer(i96, TimestampFn(.awake));
pub const Timer_boot = GenericTimer(i96, TimestampFn(.boot));
pub const Timer_cpu_process = GenericTimer(i96, TimestampFn(.cpu_process));
pub const Timer_cpu_thread = GenericTimer(i96, TimestampFn(.cpu_thread));
pub const Timer_real = GenericTimer(i96, TimestampFn(.real));
