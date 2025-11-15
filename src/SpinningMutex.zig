const builtin = @import("builtin");
const std = @import("std");
const debug = @import("debug.zig");



const Impl = if (builtin.single_threaded) SingleThreadedImpl else SpinningImpl;
const SpinningMutex = @This();

impl: Impl = .{},

pub fn tryLock(self: *@This()) bool {
    return self.impl.tryLock();
}
pub fn lock(self: *@This()) void {
    self.impl.lock();
}
pub fn unlock(self: *@This()) void {
    self.impl.unlock();
}

const SingleThreadedImpl = struct {
    is_locked: bool = false,

    fn tryLock(self: *@This()) bool {
        if (self.is_locked) return false;
        self.is_locked = true;
        return true;
    }

    fn lock(self: *@This()) void {
        const success = self.tryLock();
        debug.assertMsg(success, "Deadlock detected");
    }

    fn unlock(self: *@This()) void {
        debug.assertMsg(self.is_locked, "Mutex already unlocked");
        self.is_locked = false;
    }
};

const SpinningImpl = struct {
    const ThreadId = std.Thread.Id;
    const ThreadId0: ThreadId = std.mem.zeroes(ThreadId);
    val: ThreadId = 0,

    fn tryLock(self: *@This()) bool {
        const threadId = std.Thread.getCurrentId();
        return @cmpxchgWeak(ThreadId, &self.val, ThreadId0, threadId, std.builtin.AtomicOrder.monotonic, std.builtin.AtomicOrder.monotonic) != null;
    }

    pub fn lock(self: *@This()) void {
        const threadId = std.Thread.getCurrentId();
        while (@cmpxchgWeak(ThreadId, &self.val, ThreadId0, threadId, std.builtin.AtomicOrder.monotonic, std.builtin.AtomicOrder.monotonic) != null) {}
    }

    pub fn unlock(self: *@This()) void {
        const threadId = std.Thread.getCurrentId();
        const oldValue: ?ThreadId = @cmpxchgStrong(ThreadId, &self.val, threadId, ThreadId0, std.builtin.AtomicOrder.monotonic, std.builtin.AtomicOrder.monotonic);
        debug.assert(oldValue == null);
    }
};
