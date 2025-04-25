const std = @import("std");
const builtin = @import("builtin");

const ansi_esc = "\x1b[";
const ansi_text_reset = ansi_esc ++ "0m";
const ansi_text_fail = ansi_esc ++ "1;31m";
const ansi_text_pass = ansi_esc ++ "1;32m";
pub fn main() !void {
    const out = std.io.getStdOut().writer();

    var count_test: usize = 0;
    var count_pass: usize = 0;
    var count_fail: usize = 0;

    for (builtin.test_functions) |t| {
        count_test += 1;
        t.func() catch |err| {
            try std.fmt.format(out, "{any}{any}\n{s}FAIL{s}\t{s}\n", .{ err, @errorReturnTrace(), ansi_text_fail, ansi_text_reset, t.name });
            count_fail += 1;
            continue;
        };
        try std.fmt.format(out, "{s}PASS{s}\t{s}\n", .{ ansi_text_pass, ansi_text_reset, t.name });
        count_pass += 1;
    }

    try std.fmt.format(out, "\n=== SUMMARY ===\n", .{});
    try std.fmt.format(out, "{s}PASSED{s}\t{d}/{d}\n", .{ ansi_text_pass, ansi_text_reset, count_pass, count_test });
    if (count_fail > 0) try std.fmt.format(out, "{s}FAILED{s}\t{d}/{d}\n", .{ ansi_text_fail, ansi_text_reset, count_fail, count_test });
}

fn setCursorLineStart(writer: anytype) !void {
    _ = try writer.write("\x1b[0F\r");
}
fn clearCurrentLine(writer: anytype) !void {
    try setCursorLineStart(writer);
    _ = try writer.write("\x1b[0K");
}

fn writePass(writer: anytype, t: std.builtin.TestFn) !void {
    try clearCurrentLine(writer);
    try std.fmt.format(writer, "\x1b[32mV {s}\x1b[0m\n", .{t.name});
}
fn writeFail(writer: anytype, t: std.builtin.TestFn, err: anyerror) !void {
    try clearCurrentLine(writer);
    try std.fmt.format(writer, "\x1b[31mX {s}:\x1b[0m {}\n", .{ t.name, err });
}
fn setCursorNextLine(writer: anytype) !void {
    _ = try writer.write("\n\n");
}
