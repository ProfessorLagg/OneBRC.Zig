const builtin = @import("builtin");
const std = @import("std");

/// Uses `mask` to transfer either contiguous or non-contiguous bits in `x` to contiguous low order bit positions in the result.
/// For each bit set in `mask`, extracts the corresponding bits `x` and writes them into contiguous lower bits of the result.
/// The remaining upper bits of the result are zeroed.
export fn pext32(x: u32, mask: u32) u32 {
    return asm volatile ( // NO FOLD
        \\ pext %[mask], %[x], %[r]
        : [r] "={eax}" (-> u32),
        : [x] "{ebx}" (x),
          [mask] "{ecx}" (mask),
    );
}

/// Uses `mask` to transfer either contiguous or non-contiguous bits in `x` to contiguous low order bit positions in the result.
/// For each bit set in `mask`, extracts the corresponding bits `x` and writes them into contiguous lower bits of the result.
/// The remaining upper bits of the result are zeroed.
export fn pext64(x: u64, mask: u64) u64 {
    return asm volatile ( // NO FOLD
        \\ pext %[mask], %[x], %[r]
        : [r] "={rax}" (-> u64),
        : [x] "{rbx}" (x),
          [mask] "{rcx}" (mask),
    );
}

/// computes `dst.* +%= src` in one action.
/// Avoids race conditions when muliple threads are trying to update `dst.*` without impacting performance
pub inline fn add_direct(dst: *usize, src: usize) void {
    return asm volatile (
        \\ add %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
    );
}

/// computes `dst.* -%= src` in one action.
/// Avoids race conditions when muliple threads are trying to update `dst.*` without impacting performance
pub inline fn sub_direct(dst: *usize, src: usize) void {
    return asm volatile (
        \\ sub %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
    );
}

pub fn store_direct(dst: *usize, src: usize) void {
    return asm volatile (
        \\ mov %rax, (%rdi)
        :
        : [dst] "{rdi}" (dst),
          [src] "{rax}" (src),
    );
}

pub fn load_direct(src: *const usize) usize {
    return asm volatile (
        \\ mov (%rdi), %rax
        : [ret] "={rax}" (-> u64),
        : [src] "{rdi}" (src),
    );
}

pub fn load_direct_64(src: *const u64) u64 {
    return asm volatile (
        \\ mov (%rdi), %rax
        : [ret] "={rax}" (-> u64),
        : [src] "{rdi}" (src),
    );
}

pub fn load_direct_32(src: *const u32) u32 {
    return asm volatile (
        \\ mov (%rdi), %eax
        : [ret] "={eax}" (-> u32),
        : [src] "{rdi}" (src),
    );
}

pub fn load_direct_16(src: *const u16) u16 {
    return asm volatile (
        \\ mov (%rdi), %ax
        : [ret] "={ax}" (-> u16),
        : [src] "{rdi}" (src),
    );
}

pub fn load_direct_8(src: *const u8) u8 {
    return asm volatile (
        \\ mov (%rdi), %al
        : [ret] "={al}" (-> u8),
        : [src] "{rdi}" (src),
    );
}

/// Performs a serializing operation on all load-from-memory and store-to-memory instructions that were issued prior the mfence
pub inline fn mfence() void {
    asm volatile ("mfence");
}

/// Performs a serializing operation on all load-from-memory instructions that were issued prior the lfence
pub inline fn lfence() void {
    asm volatile ("lfence");
}

/// Performs a serializing operation on all store-to-memory instructions that were issued prior the sfence
pub inline fn sfence() void {
    asm volatile ("sfence");
}

/// Returns current TSC. Syncronizes by using mfence
pub fn rdtsc_fenced() u64 {
    return asm volatile ( // NO FOLD
        \\mfence
        \\rdtsc
        \\shl $32, %rdx
        \\or %rdx, %rax
        : [ret] "={rax}" (-> u64),
        :
        : .{ .rax = true, .rdx = true });
}

/// Returns current TSC
pub noinline fn rdtsc() u64 {
    return asm volatile ( // NO FOLD
        \\rdtsc
        \\shl $32, %rdx
        \\or %rdx, %rax
        : [ret] "={rax}" (-> u64),
        :
        : .{ .rax = true, .rdx = true });
}

pub fn rdseed16() u16 {
    return asm volatile (
        \\.loop_rdseed16:
        \\rdseed %[ret]
        \\jnc .loop_rdseed16
        : [ret] "={ax}" (-> u16),
    );
}
pub fn rdseed32() u32 {
    return asm volatile (
        \\.loop_rdseed32:
        \\rdseed %[ret]
        \\jnc .loop_rdseed32
        : [ret] "={eax}" (-> u32),
    );
}
pub fn rdseed64() u64 {
    return asm volatile (
        \\.loop_rdseed64:
        \\rdseed %[ret]
        \\jnc .loop_rdseed64
        : [ret] "={rax}" (-> u64),
    );
}

pub const CpuId = @import("cpuid.zig");
