const builtin = @import("builtin");

const c = switch (builtin.target.os.tag) {
    .windows => @cImport({
        @cInclude("memoryapi.h");
    }),
    else => struct {},
};

pub usingnamespace c;
