const std = @import("std");
const builtin = @import("builtin");

const _esc = "\x1b[";
const _text_reset = _esc ++ "0m";
const _text_test = _esc ++ "1;33m";
const _text_fail = _esc ++ "1;31m";
const _text_pass = _esc ++ "1;32m";
const _move_up_1 = _esc ++ "A";
pub fn main() !void {
    const out = std.io.getStdOut().writer();

    var count_test: usize = 0;
    var count_pass: usize = 0;
    var count_fail: usize = 0;

    for (builtin.test_functions) |t| {
        count_test += 1;
        // try std.fmt.format(out, "{s}TEST{s}    {s}\n", .{ _text_test, _text_reset, t.name });
        t.func() catch |err| {
            try std.fmt.format(out, _text_fail ++ "FAIL\t" ++ _text_reset ++ "{s}\n", .{ t.name });
            try std.fmt.format(out, "{any}\n{any}\n", .{ err, @errorReturnTrace() });
            count_fail += 1;
            continue;
        };
        try std.fmt.format(out, _text_pass ++ "PASS\t" ++ _text_reset ++ "{s}\n", .{ t.name });
        count_pass += 1;
    }

    try std.fmt.format(out, "\n=== SUMMARY ===\n", .{});
    try std.fmt.format(out, "{s}PASSED{s}\t{d}/{d}\n", .{ _text_pass, _text_reset, count_pass, count_test });
    if (count_fail > 0) try std.fmt.format(out, "{s}FAILED{s}\t{d}/{d}\n", .{ _text_fail, _text_reset, count_fail, count_test });
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
