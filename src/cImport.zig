const builtin = @import("builtin");

pub const c = switch (builtin.target.os.tag) {
    .windows => @cImport({
        @cInclude("Windows.h");
        @cInclude("memoryapi.h");
    }),
    else => struct {},
};
