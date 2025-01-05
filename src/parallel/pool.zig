const std = @import("std");
const Allocator = std.mem.Allocator;

const parallelUtils = @import("parallelUtils.zig");
const log = parallelUtils.ParallelLogScope;
// https://zig.news/kprotty/resource-efficient-thread-pools-with-zig-3291

pub const ThreadPool = @This();

pub const CallbackFn = (fn (ctx: ?*anyopaque) void);
pub const Task = struct {
    context: ?*anyopaque = null,
    callback: *const CallbackFn,
};

pub const ThreadState = enum {
    UNINITIALIZED,
    STOPPING,
    STOPPED,
    RUNNING,
    WAITING,
};
// ====== Instance Data =====
allocator: Allocator,

workQueue: std.ArrayList(Task) = undefined,
workQueueLock: std.Thread.Mutex = .{},

states: []ThreadState,
threads: []std.Thread,
threads_lock: std.Thread.Mutex = .{},

// ====== Public Functions =====
pub fn init(allocator: Allocator) ThreadPool {
    const max_thread_count = parallelUtils.get_max_thread_count() - 1;
    const r: ThreadPool = .{
        .allocator = allocator,
        .workQueue = std.ArrayList(Task).init(allocator),
        .threads = allocator.alloc(std.Thread, max_thread_count) catch {
            @panic("Out of memory!");
        },
        .states = allocator.alloc(ThreadState, max_thread_count) catch {
            @panic("Out of memory!");
        },
    };
    parallelUtils.fillSlice(ThreadState, .UNINITIALIZED, r.states);
    return r;
}
pub fn deinit(self: *ThreadPool) void {
    self.waitAll();
    self.workQueue.deinit();
    self.allocator.free(self.threads);
    self.allocator.free(self.states);
}
pub fn scheduleTask(self: *ThreadPool, task: Task) void {
    self.workQueueLock.lock();
    self.workQueue.append(task) catch {
        @panic("Out of memory!");
    };
    _ = self.startThread();
    self.workQueueLock.unlock();
}
pub fn schedule(self: *ThreadPool, context: ?*anyopaque, callback: *const CallbackFn) void {
    self.scheduleTask(Task{ .context = context, .callback = callback });
}
pub fn threadCount(self: *ThreadPool) usize {
    var result: usize = 0;
    self.threads_lock.lock();
    for (0..self.threads.len) |i| {
        result += @intFromBool(self.states[i] != .STOPPED);
    }
    self.threads_lock.unlock();
    return result;
}
pub fn waitAll(self: *ThreadPool) void {
    for (0..self.threads.len) |thread_id| {
        self.waitThread(thread_id);
    }
}
// ====== Private Functions =====
fn startThread(self: *ThreadPool) bool {
    self.threads_lock.lock();
    defer self.threads_lock.unlock();
    for (0..self.threads.len) |thread_id| {
        const thread_state: ThreadState = self.states[thread_id];
        if (thread_state == .UNINITIALIZED) {
            self.threads[thread_id] = std.Thread.spawn(.{}, threadFn, .{ self, thread_id }) catch |err| {
                log.err("Could not spawn thread due to: {any}", .{err});
                @panic("Could not spawn thread");
            };
            self.states[thread_id] = .RUNNING;
            return true;
        }
    }
    return false;
}
fn waitThread(self: *ThreadPool, thread_id: usize) void {
    self.threads_lock.lock();
    if (self.states[thread_id] == .RUNNING) {
        log.debug("{d} STOPPING  thread {d}", .{ std.time.nanoTimestamp(), thread_id });
        self.states[thread_id] = .STOPPING;
        self.threads_lock.unlock();

        self.threads[thread_id].join();

        self.threads_lock.lock();
        self.states[thread_id] = .STOPPED;
        log.debug("{d} STOPPED  thread {d}", .{ std.time.nanoTimestamp(), thread_id });
    }
    self.threads_lock.unlock();
}

fn tryGetTask(self: *ThreadPool) ?Task {
    self.workQueueLock.lock();
    defer self.workQueueLock.unlock();
    return self.workQueue.popOrNull();
}

fn threadFn(self: *ThreadPool, thread_id: usize) void {
    log.debug("{d} START thread {d}", .{ std.time.nanoTimestamp(), thread_id });
    std.debug.assert(thread_id < self.threads.len);
    self.states[thread_id] = .RUNNING;
    while (self.states[thread_id] == .RUNNING) {
        while (self.tryGetTask()) |task| {
            task.callback(task.context);
        }
    }
}
