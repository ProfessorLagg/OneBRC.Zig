const std = @import("std");
pub fn get_max_thread_count() usize {
    if (@inComptime()) {
        @compileError("This function can only be executed at runtime");
    }
    return std.Thread.getCpuCount() catch {
        return 1;
    };
}

pub fn fillSlice(comptime T: type, v: T, slice: []T) void{
    for(0..slice.len) |i| {
        slice[i] = v;
    }
}

pub const ParallelLogScope = std.log.scoped(.Parallel);
