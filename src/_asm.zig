const builtin = @import("builtin");
const std = @import("std");

const ChunkType = enum {
    simd512,
    simd256,
    simd128,
    simd64,
    scalar64,
    scalar32,
    scalar16,
    scalar8,

    const bestChunkType: ChunkType = b: {
        // TODO Figure out the best chunk type
        break :b .simd128;
    };

    const scalar: ChunkType = switch (@bitSizeOf(usize)) {
        8 => .scalar8,
        16 => .scalar16,
        32 => .scalar32,
        64 => .scalar64,
        else => unreachable,
    };

    /// Returns the size, int bits, of the chunk type
    fn bitSize(comptime chunkType: ChunkType) comptime_int {
        return switch (chunkType) {
            .simd512 => 512,
            .simd256 => 256,
            .simd128 => 128,
            .simd64 => 64,
            .scalar64 => 64,
            .scalar32 => 32,
            .scalar16 => 16,
            .scalar8 => 8,
        };
    }

    /// Retusn the size, in bytes, of the chunk type
    fn size(comptime chunkType: ChunkType) comptime_int {
        return bitSize(chunkType) / 8;
    }
};

inline fn chunkNotEql_simd256(noalias a: *align(1) const anyopaque, noalias b: *align(1) const anyopaque) bool {
    return asm volatile ( // NOFOLD
        \\ vmovups (%rsi), %ymm1
        \\ vmovups (%rdi), %ymm2
        \\ vpcmpeqb %ymm2, %ymm1, %ymm0
        \\ vpmovmskb %ymm0, %eax
        \\ cmp $-1, %eax
        \\ setne %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
        : "eax"
    );
}
inline fn chunkNotEql_simd128(noalias a: *align(1) const anyopaque, noalias b: *align(1) const anyopaque) bool {
    return asm volatile ( // NOFOLD
        \\ vmovups (%rsi), %xmm1
        \\ vmovups (%rdi), %xmm2
        \\ vpcmpeqb %xmm2, %xmm1, %xmm0
        \\ vpmovmskb %xmm0, %eax
        \\ cmp $-1, %ax
        \\ setne %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
        : "eax"
    );
}
inline fn chunkNotEql_scalar(noalias a: *align(1) const anyopaque, noalias b: *align(1) const anyopaque) bool {
    // TODO Check the assembly output here
    return @as(*align(1) const usize, @ptrCast(a)).* != @as(*align(1) const usize, @ptrCast(b)).*;
}
pub fn memeql_v0(noalias a: []const u8, noalias b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    const chunksize256: comptime_int = ChunkType.size(.simd256);
    const chunksize128: comptime_int = ChunkType.size(.simd128);
    const chunksizeScalar: comptime_int = ChunkType.size(ChunkType.scalar);
    while (true) {
        if ((a.len - i) >= chunksize256) {
            if (chunkNotEql_simd256(@ptrCast(&a[i]), @ptrCast(&b[i]))) return false;
            i += chunksize256;
            continue;
        }
        if ((a.len - i) >= chunksize128) {
            if (chunkNotEql_simd128(@ptrCast(&a[i]), @ptrCast(&b[i]))) return false;
            i += chunksize128;
            continue;
        }
        if ((a.len - i) >= chunksizeScalar) {
            if (chunkNotEql_scalar(@ptrCast(&a[i]), @ptrCast(&b[i]))) return false;
            i += chunksizeScalar;
            continue;
        }
        break;
    }
    while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;

    return true;
}

pub fn memeql_v1(noalias a: []const u8, noalias b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    const chunksize: comptime_int = 32;
    const cmax: usize = @divFloor(a.len, chunksize) * chunksize;
    var va: @Vector(chunksize, u8) = undefined;
    var vb: @Vector(chunksize, u8) = undefined;
    while (i < cmax) : (i += chunksize) {
        va = @as(*align(1) const @Vector(chunksize, u8), @ptrCast(&a[i])).*;
        vb = @as(*align(1) const @Vector(chunksize, u8), @ptrCast(&b[i])).*;
        if (@reduce(.Or, va != vb)) return false;
    }
    while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;
    return true;
}

noinline fn memeql_asm(noalias a: *align(1) const anyopaque, noalias b: *align(1) const anyopaque, len: usize) bool {
    return asm volatile ( // NOFOLD
        \\.switch:
        // if we can do 256bit / 32byte compare, we do it
        \\  cmp $32, %rcx
        \\  jge .cmp32
        // if we can do 128bit / 16byte compare, we do it
        \\  cmp $16, %rcx
        \\  jge .cmp16
        // if we can do 164bit / 8byte compare, we do it
        \\  cmp $8, %rcx
        \\  jge .cmp8
        // if we can do the scalar 1 compare, we do it
        \\  jmp .cmp1
        \\.cmp32:
        \\  vmovups (%rsi), %ymm1
        \\  vmovups (%rdi), %ymm2
        \\  add $32, %rsi
        \\  add $32, %rdi
        \\  sub $32, %rcx
        \\  vpcmpeqb %ymm2, %ymm1, %ymm0
        \\  vpmovmskb %ymm0, %eax
        \\  cmp $-1, %eax
        \\  jne .ret_false
        \\  jmp .switch
        \\.cmp16:
        \\  vmovups (%rsi), %xmm1
        \\  vmovups (%rdi), %xmm2
        \\  add $16, %rsi
        \\  add $16, %rdi
        \\  sub $16, %rcx
        \\  vpcmpeqb %xmm2, %xmm1, %xmm0
        \\  vpmovmskb %xmm0, %eax
        \\  cmp $-1, %ax
        \\  jne .ret_false
        \\  jmp .switch
        \\.cmp8:
        \\  mov (%rsi), %rax
        \\  mov (%rdi), %rbx
        \\  add $8, %rsi
        \\  add $8, %rdi
        \\  sub $8, %rcx
        \\  cmp %rax, %rbx
        \\  jne .ret_false
        \\  jmp .switch
        \\.cmp1:
        \\  cmp $0, %rcx
        \\  je .ret_true
        \\  mov (%rsi), %al
        \\  mov (%rdi), %bl
        \\  add $1, %rsi
        \\  add $1, %rdi
        \\  sub $1, %rcx
        \\  cmp %al, %bl
        \\  jne .ret_false
        \\  jmp .cmp1
        \\.ret_false:
        \\  mov $0, %al
        \\  jmp .ret
        \\.ret_true:
        \\  mov $1, %al
        \\  jmp .ret
        \\.ret:
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
          [len] "{rcx}" (len),
        : "rax", "rbx", "ymm0", "ymm1", "ymm2", "xmm0", "xmm1", "xmm2"
    );
}
pub fn memeql_v2(noalias a: []const u8, noalias b: []const u8) bool {
    if (a.len != b.len) return false;
    return memeql_asm(@ptrCast(&a[0]), @ptrCast(&b[0]), a.len);
}

export fn repe_cmpsb(noalias a: *align(1) const anyopaque, noalias b: *align(1) const anyopaque, len: usize) bool {
    return asm volatile ( // NOFOLD
        \\ repe cmpsb
        \\ sete %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a),
          [b] "{rdi}" (b),
          [len] "{rcx}" (len),
    );
}
pub fn memeql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    return asm volatile ( // NOFOLD
        \\ repe cmpsb
        \\ sete %al
        : [ret] "={al}" (-> bool),
        : [a] "{rsi}" (a.ptr),
          [b] "{rdi}" (b.ptr),
          [len] "{rcx}" (a.len),
    );
}

/// computes dst.* +%= src in one action.
/// Avoids race conditions when muliple threads are trying to update `dst.*` without impacting performance
pub inline fn add_direct(dst: *usize, src: usize) void {
    return asm volatile (
        \\ add %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
        : "rax"
    );
}

/// computes dst.* -%= src in one action.
/// Avoids race conditions when muliple threads are trying to update `dst.*` without impacting performance
pub inline fn sub_direct(dst: *usize, src: usize) void {
    return asm volatile (
        \\ sub %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
        : "rax"
    );
}