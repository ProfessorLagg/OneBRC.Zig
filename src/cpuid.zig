const builtin = @import("builtin");
const std = @import("std");

pub const RawResult = packed struct { eax: u32, ebx: u32, ecx: u32, edx: u32 };
fn cpuidex_interal(leaf: u32, extention: u32, output: *[4]u32) void {
    return asm volatile (
        \\xor %ebx, %ebx
        \\xor %edx, %edx
        \\cpuid
        \\movl %eax, (%[out])
        \\movl %ebx, 4(%[out])
        \\movl %ecx, 8(%[out])
        \\movl %edx, 12(%[out])
        :
        : [fid] "{eax}" (leaf),
          [sid] "{ecx}" (extention),
          [out] "{rdi}" (output),
        : .{ .eax = true, .ebx = true, .ecx = true, .edx = true });
}
pub fn cpuidex(leaf: u32, extention: u32) RawResult {
    var result: [4]u32 = undefined;
    cpuidex_interal(leaf, extention, &result);
    return @bitCast(result);
}
pub fn cpuid(leaf: u32) RawResult {
    return @call(.always_inline, cpuidex, .{ leaf, 0 });
}

/// Maximum leaf and vendor id
pub const Leaf0 = struct { // https://en.wikipedia.org/wiki/CPUID#EAX=0:_Highest_Function_Parameter_and_Manufacturer_ID
    var cached: ?Leaf0 = null;
    maxLeaf: u32,
    vendorId: [12]u8,
    pub fn get() Leaf0 {
        if (cached == null) {
            cached = undefined;
            const raw = cpuid(0);
            cached.?.maxLeaf = raw.eax;
            const vid_u32_ptr: *align(1) [3]u32 = @ptrCast(&cached.?.vendorId);
            vid_u32_ptr[0] = raw.ebx;
            vid_u32_ptr[1] = raw.edx;
            vid_u32_ptr[2] = raw.ecx;
        }
        return cached.?;
    }
};

/// https://en.wikipedia.org/wiki/CPUID#EAX=15h_and_EAX=16h:_CPU,_TSC,_Bus_and_Core_Crystal_Clock_Frequencies
pub const Leaf15 = struct {
    var cached: ?Leaf15 = null;
    tsc_to_crystal_denominator: u32 = 0,
    tsc_to_crystal_numerator: u32 = 0,
    coreCrystalClockHz: u32 = 0,
    tscHz: ?u64 = null,

    pub fn get() Leaf15 {
        if (cached == null) {
            cached = .{};
            const raw = cpuid(0x15);
            cached.?.tsc_to_crystal_denominator = raw.eax;
            cached.?.tsc_to_crystal_numerator = raw.ebx;
            cached.?.coreCrystalClockHz = raw.ecx;
            // If the returned values in EBX and ECX of leaf 0x15 are both nonzero, then the TSC (Time Stamp Counter) frequency in Hz is given by TSCFreq = ECX*(EBX/EAX).
            if (raw.ebx != 0 and raw.ecx != 0) {
                cached.?.tscHz = @as(u64, raw.ecx) * (@as(u64, raw.ebx) / @as(u64, raw.eax));
            }
        }
        return cached.?;
    }
};

pub const Leaf1 = @compileError("Not yet implemented");
pub const Leaf2 = @compileError("Not yet implemented");
pub const Leaf3 = @compileError("Not yet implemented");
pub const Leaf4 = @compileError("Not yet implemented");
pub const Leaf5 = @compileError("Not yet implemented");
pub const Leaf6 = @compileError("Not yet implemented");
pub const Leaf7 = @compileError("Not yet implemented");
pub const Leaf8 = @compileError("Not yet implemented");
pub const Leaf9 = @compileError("Not yet implemented");
pub const LeafA = @compileError("Not yet implemented");
pub const LeafB = @compileError("Not yet implemented");
pub const LeafC = @compileError("Not yet implemented");
pub const LeafD = @compileError("Not yet implemented");
pub const LeafE = @compileError("Not yet implemented");
pub const LeafF = @compileError("Not yet implemented");
pub const Leaf10 = @compileError("Not yet implemented");
pub const Leaf11 = @compileError("Not yet implemented");
pub const Leaf12 = @compileError("Not yet implemented");
pub const Leaf13 = @compileError("Not yet implemented");
pub const Leaf14 = @compileError("Not yet implemented");
pub const Leaf16 = @compileError("Not yet implemented");
pub const Leaf17 = @compileError("Not yet implemented");
pub const Leaf18 = @compileError("Not yet implemented");
pub const Leaf19 = @compileError("Not yet implemented");
pub const Leaf1A = @compileError("Not yet implemented");
pub const Leaf1B = @compileError("Not yet implemented");
pub const Leaf1C = @compileError("Not yet implemented");
pub const Leaf1D = @compileError("Not yet implemented");
pub const Leaf1E = @compileError("Not yet implemented");
pub const Leaf1F = @compileError("Not yet implemented");
