const builtin = @import("builtin");
const std = @import("std");

const ThreadId = std.Thread.Id;
const ThreadId0: ThreadId = std.mem.zeroes(ThreadId);
const SpinningMutex = @This();

val: ThreadId = 0,

pub fn lock(self: *SpinningMutex) void {
    const threadId = std.Thread.getCurrentId();
    while (@cmpxchgWeak(ThreadId, &self.val, ThreadId0, threadId, std.builtin.AtomicOrder.monotonic, std.builtin.AtomicOrder.monotonic) != null) {}
}

pub fn unlock(self: *SpinningMutex) void {
    const threadId = std.Thread.getCurrentId();
    _ = @cmpxchgStrong(ThreadId, &self.val, threadId, ThreadId0, std.builtin.AtomicOrder.monotonic, std.builtin.AtomicOrder.monotonic);
}
