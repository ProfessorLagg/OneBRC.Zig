const builtin = @import("builtin");
const std = @import("std");

fn assertSupportsFeature(comptime feature: std.Target.x86.Feature) void {
    comptime {
        const featureEnabled = builtin.cpu.features.isEnabled(@intFromEnum(feature));
        if (!featureEnabled) @compileError("expected cpu feature " ++ @tagName(feature) ++ " to be enabled, but found disabled");
    }
}
comptime {
    const assertArchitechture: std.Target.Cpu.Arch = .x86_64;
    if (builtin.cpu.arch != assertArchitechture) @compileError("Expected cpu architecture to be " ++ @tagName(assertArchitechture) ++ ", but found " ++ @tagName(builtin.cpu.arch));
    // assertSupportsFeature(std.Target.x86.Feature.adx);
    // assertSupportsFeature(std.Target.x86.Feature.aes);
    assertSupportsFeature(std.Target.x86.Feature.avx);
    assertSupportsFeature(std.Target.x86.Feature.avx2);
    assertSupportsFeature(std.Target.x86.Feature.bmi2);
    assertSupportsFeature(std.Target.x86.Feature.bmi);
    // assertSupportsFeature(std.Target.x86.Feature.f16c);
    assertSupportsFeature(std.Target.x86.Feature.mmx);
    assertSupportsFeature(std.Target.x86.Feature.sha);
    assertSupportsFeature(std.Target.x86.Feature.sse);
    assertSupportsFeature(std.Target.x86.Feature.sse2);
    assertSupportsFeature(std.Target.x86.Feature.sse3);
    assertSupportsFeature(std.Target.x86.Feature.ssse3);
    assertSupportsFeature(std.Target.x86.Feature.sse4_1);
    assertSupportsFeature(std.Target.x86.Feature.sse4_2);
    assertSupportsFeature(std.Target.x86.Feature.sse4a);
}