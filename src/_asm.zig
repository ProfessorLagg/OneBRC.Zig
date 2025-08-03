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
pub fn x86_fnv1a_32(ptr: *const anyopaque, len: usize) u32 {
    return asm volatile (
    // zero out registers
        \\xor %rbx, %rbx
        \\xor %rax, %rax
        // Mov offset into rax
        \\mov $0x811c9dc5, %rax
        // move prime into r8
        \\mov $0x01000193, %r8
        \\.x86_fnv1a_32_ex_hashbyte:
        // return if %cnt is 0
        \\  cmp $0, %rcx
        \\  je .x86_fnv1a_32_ex_ret
        // move byte from %rdi into %bl
        \\  movb (%rdi), %bl
        //
        \\  xor %bl, %al
        //
        \\  mul %r8
        //
        \\  inc %rdi
        //
        \\  dec %rcx
        \\ jmp .x86_fnv1a_32_ex_hashbyte
        \\.x86_fnv1a_32_ex_ret:
        : [ret] "={rax}" (-> u32),
        : [ptr] "{rdi}" (ptr),
          [cnt] "{rcx}" (len),
        : "rax", "r8", "bl", "rbx"
    );
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

/// computes dst.* +%= src in one action.
/// Avoids race conditions when muliple threads are trying to update `dst.*` without impacting performance
pub inline fn sumDirect(dst: *usize, src: usize) void {
    return asm volatile (
        \\ add %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
        : "rax"
    );
}

test sumDirect {
    const allocator: std.mem.Allocator = std.testing.allocator;
    const len: comptime_int = 111;
    var prng = std.Random.DefaultPrng.init(2025_08_02);

    const src: []usize = try allocator.alloc(usize, len);
    defer allocator.free(src);
    const exp: []usize = try allocator.alloc(usize, len);
    defer allocator.free(exp);
    const fnd: []usize = try allocator.alloc(usize, len);
    defer allocator.free(fnd);

    prng.fill(std.mem.sliceAsBytes(src));
    prng.fill(std.mem.sliceAsBytes(exp));
    @memcpy(fnd, exp);

    for (0..len) |i| {
        const exp_ptr: *usize = &exp[i];
        const fnd_ptr: *usize = &fnd[i];

        const exp_org: usize = exp_ptr.*;
        const fnd_org: usize = fnd_ptr.*;

        exp_ptr.* +%= src[i];
        sumDirect(fnd_ptr, src[i]);

        std.testing.expectEqual(exp[i], fnd[i]) catch |e| {
            std.log.err("expect {d} +%= {d} == {d}", .{ src[i], exp_org, exp[i] });
            std.log.err("found  {d} +%= {d} == {d}", .{ src[i], fnd_org, fnd[i] });
            return e;
        };
    }
}

pub const Register256 = enum {
    ymm1,
    ymm3,
    ymm5,
    ymm7,
    ymm9,
    ymm11,
    ymm13,
    ymm15,
};
/// Loads 32 bytes / 256 bits of data from `ptr` into `register`
pub inline fn load256(comptime register: Register256, ptr: *anyopaque) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx))) @compileError("this function requires avx");
    return asm volatile ( // NO FOLD
        "vlddqu (%rsi), %" ++ @tagName(register)
        :
        : [ptr] "{rsi}" (ptr),
    );
}

/// stores 32 bytes / 256 bits from `register` into `ptr`
pub inline fn store256(comptime register: Register256, ptr: *anyopaque) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx))) @compileError("this function requires avx");
    return asm volatile ( // NO FOLD
        "vmovdqu %" ++ @tagName(register) ++ ", (%rdi)"
        :
        : [ptr] "{rdi}" (ptr),
    );
}

/// Sets all 32 values of `register` to `v`
pub inline fn set256_8(comptime register: Register256, v: u8) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) @compileError("this function requires avx2");
    return asm volatile ( //NO FOLD
        "vpbroadcastb %ah, %" ++ @tagName(register)
        :
        : [v] "ah" (v),
    );
}

/// Sets all 16 values of `register` to `v`
pub inline fn set256_16(comptime register: Register256, v: u16) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) @compileError("this function requires avx2");
    return asm volatile ( //NO FOLD
        "vpbroadcastb %ax, %" ++ @tagName(register)
        :
        : [v] "ax" (v),
    );
}

/// Sets all 8 values of `register` to `v`
pub inline fn set256_32(comptime register: Register256, v: u32) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) @compileError("this function requires avx2");
    return asm volatile ( //NO FOLD
        "vpbroadcastb %eax, %" ++ @tagName(register)
        :
        : [v] "eax" (v),
    );
}

/// Sets all 4 values of `register` to `v`
pub inline fn set256_64(comptime register: Register256, v: u64) void {
    comptime if (!builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) @compileError("this function requires avx2");
    return asm volatile ( //NO FOLD
        "vpbroadcastb %rax, %" ++ @tagName(register)
        :
        : [v] "rax" (v),
    );
}