const builtin = @import("builtin");
const std = @import("std");

pub const os = @import("os.zig");
pub const intrinsics = @import("intrinsics.zig");

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

pub const fs = struct {
    const WindowsImpl = struct {
        const winos = std.os.windows;
        const FileW = struct {
            handle: std.os.windows.HANDLE = winos.INVALID_HANDLE_VALUE,

            pub fn close(self: @This()) void {
                winos.CloseHandle(self.handle);
            }
        };
        fn openFile(filePath: []const u8) !FileW {
            const access_mask: winos.ACCESS_MASK = .{
                .STANDARD = .{ .SYNCHRONIZE = true },
                .GENERIC = .{
                    .READ = true,
                    //.WRITE = false, // TODO Actually pass options
                },
            };

            var pathBuf: [260]std.os.windows.WCHAR = undefined;
            const pathLen: usize = try std.unicode.wtf8ToWtf16Le(pathBuf[0..], filePath);
            var path: winos.UNICODE_STRING = .init(pathBuf[0..pathLen]);
            const objectAttributes: winos.OBJECT.ATTRIBUTES = .{
                // .RootDirectory = std.Io.Dir.cwd().handle,
                .ObjectName = &path,
                .Attributes = .{
                    .CASE_INSENSITIVE = true,
                    .INHERIT = true,
                },
            };
            var io_status_block: winos.IO_STATUS_BLOCK = undefined;
            var file: FileW = .{};
            const status: winos.NTSTATUS = winos.ntdll.NtOpenFile(
                &file.handle, // FileHandle: *HANDLE
                access_mask, // DesiredAccess: ACCESS_MASK
                &objectAttributes, // ObjectAttributes: *const OBJECT.ATTRIBUTES
                &io_status_block, // IoStatusBlock: *IO_STATUS_BLOCK
                .{ .READ = true }, //ShareAccess: FILE.SHARE
                .{ .NO_INTERMEDIATE_BUFFERING = true, .IO = .SYNCHRONOUS_NONALERT }, // OpenOptions: FILE.MODE
            );
            return switch (status) {
                .SUCCESS => file,
                else => winos.unexpectedStatus(status),
            };
        }
        fn closeFile(file: FileW) void {
            file.close();
        }
        fn readFile(file: File, buffer: []u8) !usize {
            //pub extern "ntdll" fn NtReadFile(
            //    FileHandle: HANDLE,
            //    Event: ?HANDLE,
            //    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
            //    ApcContext: ?*anyopaque,
            //    IoStatusBlock: *IO_STATUS_BLOCK,
            //    Buffer: *anyopaque,
            //    Length: ULONG,
            //    ByteOffset: ?*const LARGE_INTEGER,
            //    Key: ?*const ULONG,
            //) callconv(.winapi) NTSTATUS;
            const len: winos.ULONG = @intCast(@min(buffer.len, std.math.maxInt(winos.ULONG)));
            var io_status_block: winos.IO_STATUS_BLOCK = undefined;
            const status: winos.NTSTATUS = winos.ntdll.NtReadFile(
                file.handle, // FileHandle: HANDLE
                null, // Event: ?HANDLE
                null, // ApcRoutine: ?*align(2) const IO_APC_ROUTINE
                null, // ApcContext: ?*anyopaque
                &io_status_block, // IoStatusBlock: *IO_STATUS_BLOCK,
                @ptrCast(buffer.ptr), // Buffer: *anyopaque
                len, // Length: ULONG,
                null, // ByteOffset: ?*const LARGE_INTEGER
                null, // Key: ?*const ULONG
            );
            return switch (status) {
                .SUCCESS => return io_status_block.Information,
                else => winos.unexpectedStatus(status),
            };
        }
    };

    const Impl = switch (builtin.os.tag) {
        .windows => WindowsImpl,
        else => @compileError("Not yet implemented"),
    };

    pub const File: type = Impl.FileW;
    pub const openFile: fn (filePath: []const u8) anyerror!File = Impl.openFile;
    pub const closeFile: fn (file: File) void = Impl.closeFile;
    pub const readFile: fn (file: File, buffer: []u8) anyerror!usize = Impl.readFile;
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

test "Imports" {
    _ = os;
    _ = intrinsics;
}
