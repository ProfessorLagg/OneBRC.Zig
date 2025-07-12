const builtin = @import("builtin");
const std = @import("std");

comptime {
    if (builtin.target.cpu.arch != .x86_64) @compileError("This file only works on x86_64");
}
/// Parses an UTF-8 char as an unsigned 8bit int. Non numeric values return 0
pub fn char_to_val(c: u8) u8 {
    const r: u8 = asm (
        \\mov %bl, %al
        \\sub $48, %al
        \\cmp $48, %bl
        \\setae %cl
        \\cmp $57, %bl
        \\setbe %bl
        \\mul %bl
        \\mul %cl
        : [ret] "={al}" (-> u8),
        : [c] "{bl}" (c),
        : "cl"
    );
    return r;
}

test char_to_val {
    std.log.warn("Test not implemented", .{});
}

///  Move len bytes from src to dst
pub noinline fn repmovsb(noalias dst: *anyopaque, noalias src: *const anyopaque, len: usize) void {
    // https://www.felixcloutier.com/x86/rep:repe:repz:repne:repnz
    asm volatile ( // NO FOLD
        "rep movsb"
        :
        : [src] "{rsi}" (src),
          [dst] "{rdi}" (dst),
          [len] "{rcx}" (len),
    );
}

test repmovsb {
    const prng: type = std.Random.DefaultPrng;
    const allocator = std.heap.page_allocator;
    const page_size = std.heap.pageSize();

    const src_page: []u8 = try allocator.alloc(u8, page_size);
    defer allocator.free(src_page);

    const dst_page: []u8 = try allocator.alloc(u8, page_size);
    defer allocator.free(dst_page);

    var rand: prng = prng.init(std.testing.random_seed);
    rand.fill(src_page);

    repmovsb(dst_page.ptr, src_page.ptr, src_page.len);

    try std.testing.expectEqualSlices(u8, src_page, dst_page);
}

// pub noinline fn repecmpsb(noalias dst: *anyopaque, noalias src: *const anyopaque, len: usize) usize {
//     // https://www.felixcloutier.com/x86/rep:repe:repz:repne:repnz
//     return asm volatile (
//         \\repe cmpsb
//         : [ret] "={rcx}" (-> usize),
//         : [src] "{rsi}" (src),
//           [dst] "{rdi}" (dst),
//           [len] "{rcx}" (len),
//     );
// }

// fn cmpstr(a: [*]u8, b: [*]u8, l: usize) i8 {
//     const inverse_index = repecmpsb(a, b, l);

//     // TODO Could just be a seta / setb inside the asm
//     const idx: usize = l - inverse_index;
//     const lt: i8 = @intFromBool(a[idx] < b[idx]) * @as(i8, -1);
//     const gt: i8 = @intFromBool(a[idx] > b[idx]);
//     return lt + gt;
// }

// fn cmpstr_check(a: [*]u8, b: [*]u8, l: usize) i8 {
//     @setRuntimeSafety(false);
//     var cmp: i8 = undefined;
//     var i: usize = 0;
//     while (i < l) {
//         const lt: i8 = @intFromBool(a[i] < b[i]);
//         const gt: i8 = @intFromBool(a[i] > b[i]);
//         cmp -= lt;
//         cmp += gt;
//         if (cmp == 0) break;
//         i += 1 + (l * @intFromBool(cmp != 0));
//     }
//     return cmp;
// }

// test cmpstr {
//     const seed: u64 = 2025_07_11;
//     var prng = std.Random.DefaultPrng.init(seed);
//     const rand: std.Random = prng.random();

//     for (0..17) |_| {
//         const l: usize = rand.intRangeAtMost(usize, 0, 100);
//         const a: []u8 = try std.testing.allocator.alloc(u8, l);
//         defer std.testing.allocator.free(a);
//         const b: []u8 = try std.testing.allocator.alloc(u8, l);
//         defer std.testing.allocator.free(b);
//         for (0..l) |j| {
//             a[j] = rand.intRangeAtMost(u8, 33, 126);
//             b[j] = rand.intRangeAtMost(u8, 33, 126);
//         }

//         const cmp_e = cmpstr_check(a.ptr, b.ptr, l);
//         const cmp_f = cmpstr(a.ptr, b.ptr, l);
//         try std.testing.expectEqual(cmp_e, cmp_f);
//     }
// }
