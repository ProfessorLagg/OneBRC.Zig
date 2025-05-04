const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single_threaded: bool = true;
    const link_libc: bool = true;
    const use_llvm: bool = true;

    var build_gen: bool = false;
    _ = &build_gen;

    var build_waf: bool = false;
    _ = &build_waf;

    const exe = b.addExecutable(.{
        .name = "1brc.cli",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .link_libc = link_libc,
        .use_llvm = use_llvm,
        .strip = false,
    });
    b.installArtifact(exe);

    if (build_gen) {
        const utils_module = b.addModule("utils", .{ .root_source_file = b.path("src/utils.zig") });
        const gen = b.addExecutable(.{
            .name = "1brc.gen",
            .root_source_file = b.path("src/generator/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = single_threaded,
            .link_libc = false,
            .use_llvm = true,
            .strip = true,
        });
        gen.root_module.addImport("utils", utils_module);
        b.installArtifact(gen);
    }

    if (build_waf) {
        const exe_waf = b.addUpdateSourceFiles();
        const exe_waf_path = "zig-out/bin/1brc.cli.asm";
        exe_waf.addCopyFileToSource(exe.getEmittedAsm(), exe_waf_path);
        exe_waf.step.dependOn(&exe.step);
        b.getInstallStep().dependOn(&exe_waf.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.has_side_effects = true;

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // ============ TESTING ============
    const test_step = b.step("test", "Run unit tests");

    // cli
    const cli_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
        .single_threaded = single_threaded,
        // .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_cli_unit_tests = b.addRunArtifact(cli_unit_tests);
    test_step.dependOn(&run_cli_unit_tests.step);

    // sorted
    const sorted_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sorted/sorted.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
        .single_threaded = single_threaded,
        // .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_sorted_unit_tests = b.addRunArtifact(sorted_unit_tests);
    test_step.dependOn(&run_sorted_unit_tests.step);

    // parsing
    const parsing_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/parsing.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
        .single_threaded = single_threaded,
        // .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_parsing_unit_tests = b.addRunArtifact(parsing_unit_tests);
    test_step.dependOn(&run_parsing_unit_tests.step);
}
