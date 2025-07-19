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

// pub inline fn compare_u8(a: u8, b: u8) i8 {
//     return asm volatile (
//         \\mov $0, %ax
//         \\cmp %[b], %[a]
//         \\seta %al
//         \\setb %bl
//         \\sub %al, %bl
//         : [ret] "={al}" (-> i8),
//         : [a] "{al}" (a),
//           [b] "{bl}" (b),
//     );
// }

// fn compare_u8_safe(a: u8, b: u8) i8 {
//     if (a < b) return -1;
//     if (a > b) return 1;
//     return 0;
// }

// test compare_u8 {
//     const max_u8: u8 = std.math.maxInt(u8);
//     var a: u8 = 0;
//     while (a < max_u8) : (a += 1) {
//         var b: u8 = 0;
//         while (b < max_u8) : (b += 1) {
//             const safe = compare_u8_safe(a, b);
//             const _asm = compare_u8(a, b);
//             std.testing.expectEqual(safe, _asm) catch |e| {
//                 std.log.err("expected compare({d},{d}) == {d}, but found {d}", .{ a, b, safe, _asm });
//                 return e;
//             };
//         }
//     }
// }
