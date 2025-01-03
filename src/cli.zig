const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const lib = @import("lib.zig");
const SetParser = lib.SetParser;

pub const std_options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseSmall => .info,
        .ReleaseFast => .warn,
    },
};

// TODO go through and set every parameter of the GeneralPurposeAllocator.Config
var gpa: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){};
var main_allocator: Allocator = undefined;
var parser: SetParser = undefined;
pub fn main() !void {
    try init();
    defer deinit();

    // TODO parse console args
    // const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\verysmall.txt";
    // const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\small.txt";
    const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\medium.txt";
    // const path = "C:\\CodeProjects\\1BillionRowChallenge\\data\\large.txt";
    var timer = try std.time.Timer.start();
    var parseResult = try parser.parse(path[0..]);
    defer parseResult.deinit();
    const ns: f64 = @floatFromInt(timer.read());
    const s: f64 = ns / std.time.ns_per_s;
    const ns_per_line: f64 = ns / @as(f64, @floatFromInt(parseResult.lineCount));

    // Turn this into a cli argument
    const lineCount_f64: f64 = @floatFromInt(parseResult.lineCount);
    const uniqueKeys = parseResult.uniqueKeys();
    const keyCount_f64: f64 = @floatFromInt(uniqueKeys);
    const key_percent: f64 = (keyCount_f64 / lineCount_f64) * 100;
    std.log.warn("read {d:.0} lines in {d:.2} s | {d:.2} ns/line | found {d} unique keys ({d:.2}%)", .{ parseResult.lineCount, s, ns_per_line, uniqueKeys, key_percent});
}

fn init() !void {
    main_allocator = gpa.allocator();
    parser = SetParser.init(main_allocator);
}
fn deinit() void {
    parser.deinit();

    const gpa_deinit_status = gpa.deinit();
    switch (gpa_deinit_status) {
        .ok => std.log.debug("GeneralPurposeAllocator deninit status: OK", .{}),
        .leak => std.log.warn("GeneralPurposeAllocator deninit status: LEAK", .{}),
    }
}
