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
          [mask] "{exc}" (mask),
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
        : "rax"
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
        : "rax"
    );
}
