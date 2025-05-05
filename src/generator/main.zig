const builtin = @import("builtin");
const std = @import("std");
const CityNames = @import("worldcities.zig").CityNames;
const utils = @import("utils");

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseSmall => .err,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{},
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

const mantxt = @embedFile("man.txt");
pub fn main() !void {
    init();
    defer deinit();
    const stdout = std.io.getStdOut().writer();
    const options: GenOptions = GenOptions.parseCLI() catch |err| {
        printErr("Could not parse args:", err, @errorReturnTrace());
    };
    defer options.deinit();
    try std.fmt.format(stdout, "Parsed options: Line count = {d:.0} | Output File: \"{s}\"\n", .{ options.num_lines, options.output_filepath });

    const result: RunResult = run(&options) catch |err| printErr("Run failed", err, @errorReturnTrace());
    Console.clearCurrentLine();
    Console.printf("Finished writing {d} lines | {d} bytes to \"{s}\" | generated at: {d} ns/line | {d:.3}/s", .{
        result.linesWritten,
        result.bytesWritten,
        options.output_filepath,
        result.nsPerLine(),
        std.fmt.fmtIntSizeBin(result.bytesPerSecond()),
    });
}

const RunResult = struct {
    linesWritten: u64 = 0,
    bytesWritten: u64 = 0,
    runtime_ns: u64 = 0,

    pub fn nsPerLine(self: *const RunResult) f64 {
        if (self.linesWritten <= 0) return 0;
        std.debug.assert(self.linesWritten > 0);

        const numer: f64 = @floatFromInt(self.runtime_ns);
        const denom: f64 = @floatFromInt(self.linesWritten);
        return numer / denom;
    }

    pub fn bytesPerSecond(self: *const RunResult) u64 {
        if (self.bytesWritten <= 0) return 0;
        std.debug.assert(self.bytesWritten > 0);

        const numer: f64 = @floatFromInt(self.bytesWritten);
        const denom: f64 = @as(f64, @floatFromInt(self.runtime_ns)) / @as(f64, std.time.ns_per_s);
        return @intFromFloat(numer / denom);
    }
};

fn run(options: *const GenOptions) !RunResult {
    const stdout = std.io.getStdOut().writer();
    const file: std.fs.File = options.openOutputFile() catch |err| {
        printErr("Could not open output file:", err, @errorReturnTrace());
    };
    var writer = std.io.bufferedWriter(file.writer());

    var prng = std.Random.DefaultPrng.init(getSeed());
    var rand: std.Random = prng.random();
    var linebuf: [128]u8 = undefined;

    const prog_max_f: f64 = @floatFromInt(options.num_lines);
    var prog_cur_f: f64 = 0.0;
    const prog_act = "Writing Lines";
    const prog_freq: u64 = std.time.ns_per_s / 2;
    var result: RunResult = .{};
    try std.fmt.format(stdout, "Begun Writing {d} lines to \"{s}\"\n", .{ options.num_lines, options.output_filepath });
    var timer = std.time.Timer.start() catch |err| printErr("Could not start timer", err, @errorReturnTrace());

    while (result.linesWritten < options.num_lines) {
        const name_idx: u32 = rand.intRangeLessThan(u32, 0, CityNames.len);
        const value: f64 = utils.math.map(f64, rand.float(f64), 0.0, 1.0, -99.9, 99.9);
        const line = try std.fmt.bufPrint(linebuf[0..], "{s};{d:.1}\n", .{ CityNames[name_idx], value });
        const bytesWritten = try writer.write(line);
        result.linesWritten += @intFromBool(bytesWritten > 0);
        result.bytesWritten += bytesWritten;
        if (result.linesWritten == 0 or timer.read() % prog_freq == 0) {
            prog_cur_f = @floatFromInt(result.linesWritten);
            const prog_f: f64 = @floor(utils.math.map(f64, prog_cur_f, 0.0, prog_max_f, 0.0, 100.0));
            const prog: u7 = @intFromFloat(prog_f);
            Console.writeProgress(prog_act[0..], prog);
        }
    }
    try writer.flush();
    result.runtime_ns = timer.read();
    return result;
}

fn printErr(msg: []const u8, err: anyerror, trace: ?*std.builtin.StackTrace) noreturn {
    std.log.err("{s}\n{any}{any}\n{s}\n", .{ msg, err, trace, mantxt });
    unreachable;
}

fn init() void {
    allocator = gpa.allocator();
}
fn deinit() void {
    _ = gpa.deinit();
}

fn getSeed() u64 {
    const now_ns_i128: i128 = std.time.nanoTimestamp();
    const now_ns_u128: u128 = @intCast(now_ns_i128);
    const seed: u64 = @truncate(now_ns_u128);
    return seed + 1;
}

const GenOptions = struct {
    num_lines: usize = 0,
    output_filepath: []const u8 = undefined,
    // TODO Add optional seed arg

    const ParseCliError = error{
        TooFewArguments,
        TooManyArguments,
    };
    pub fn parseCLI() !GenOptions {
        var base_args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, base_args);

        const args = base_args[1..];
        if (args.len < 2) return ParseCliError.TooFewArguments;
        if (args.len > 2) return ParseCliError.TooManyArguments;
        var result: GenOptions = GenOptions{};
        result.num_lines = @intCast(utils.math.fastIntParse(isize, args[0]));
        result.output_filepath = try utils.fs.toAbsolutePath(allocator, args[1]);

        // TODO return error if output_path is not a valid file
        return result;
    }

    pub fn openOutputFile(self: *const GenOptions) !std.fs.File {
        const file_flags: std.fs.File.CreateFlags = comptime std.fs.File.CreateFlags{
            .read = true,
            .truncate = true,
            .exclusive = true,
            .lock = .exclusive,
        };

        const output_dirpath = std.fs.path.dirname(self.output_filepath) orelse {
            printErr("output has no dirpath", std.fs.File.OpenError.BadPathName, @errorReturnTrace());
        };
        var output_dir_opt: ?std.fs.Dir = std.fs.openDirAbsolute(output_dirpath, .{}) catch null;
        if (output_dir_opt == null) {
            std.fs.makeDirAbsolute(output_dirpath) catch |err| {
                printErr("Could not open or create output directory", err, @errorReturnTrace());
            };
            output_dir_opt = std.fs.openDirAbsolute(output_dirpath, .{}) catch |err| {
                printErr("Could not open or create output directory", err, @errorReturnTrace());
            };
        }
        std.debug.assert(output_dir_opt != null);
        var output_dir = output_dir_opt.?;
        defer output_dir.close();
        const output_filename = std.fs.path.basename(self.output_filepath);
        _ = output_dir.deleteFile(output_filename) catch null;
        const output_file = try output_dir.createFile(output_filename, file_flags);
        return output_file;
    }

    pub fn deinit(self: *const GenOptions) void {
        allocator.free(self.output_filepath);
    }
};

const LineGenerator = struct {
    const TPrng = std.Random.DefaultPrng;

    buffer: [128]u8 = undefined,
    lines_left: usize = 0,

    rand_u64_val: u64 = 0,
    fn rand_u64(self: *LineGenerator) u64 {
        // TODO this could be a LFSR instead

        const max_u64: comptime_int = std.math.maxInt(u64);
        const addval: u128 = @as(u128, @intCast(@abs(std.time.nanoTimestamp()))) % max_u64;
        self.rand_u64_val *%= @intCast(addval);
        self.rand_u64_val += @intFromBool(self.rand_u64_val == 0);
        return self.rand_u64_val;
    }
    fn rand_f64(self: *LineGenerator) f64 {
        const max_u64: comptime_int = std.math.maxInt(u64);
        const max_u64_f: comptime_float = @floatFromInt(max_u64);

        const rand_f: f64 = @floatFromInt(self.rand_u64());
        return rand_f / max_u64_f;
    }

    pub fn initSeeded(line_count: usize, seed: u64) LineGenerator {
        std.log.debug("LineGenerator.init(line_count: {d}, seed: 0x{X:8})", .{ line_count, seed });
        var r = LineGenerator{};

        r.lines_left = line_count;
        r.rand_u64_val = seed;

        return r;
    }

    pub fn init(line_count: usize) LineGenerator {
        return initSeeded(line_count, getSeed());
    }

    pub fn nextLine(self: *LineGenerator) ?[]const u8 {
        if (self.lines_left == 0) return null;

        const name_idx: u64 = self.rand_u64() % CityNames.len;
        const value: f64 = utils.math.map(f64, self.rand_f64(), 0.0, 1.0, -99.9, 99.9);

        @memset(self.buffer[0..], 0);
        const result: []const u8 = std.fmt.bufPrint(self.buffer[0..], "{s};{d:.1}", .{ CityNames[name_idx], value }) catch |err| {
            std.log.err("error in LineGenerator.nextLine():" ++ " {any}{any}", .{ err, @errorReturnTrace() });
            unreachable;
        };
        self.lines_left -= 1;
        return result;
    }
};

const Console = struct {
    // const ANSI_ESC = "\x1B";
    const ANSI_ESC = [_]u8{0x1B};
    pub fn printf(comptime fmt: []const u8, args: anytype) void {
        const stdout = std.io.getStdOut().writer();
        std.fmt.format(stdout, fmt, args) catch |err| printErr("Could not print to stdout", err, @errorReturnTrace());
    }
    pub fn print(comptime fmt: []const u8) void {
        printf(fmt, .{});
    }
    pub fn clearCurrentLine() void {
        print(ANSI_ESC ++ "[2K\r");
    }
    pub fn hideCursor() void {
        print(ANSI_ESC ++ "[?25l");
    }
    pub fn showCursor() void {
        print(ANSI_ESC ++ "[?25h");
    }

    pub fn writeProgress(activity: []const u8, progress: u7) void {
        const prog: u7 = std.math.clamp(progress, 0, 100);
        var bar: [100]u8 = undefined;
        @memset(bar[0..], ' ');
        for (0..prog) |i| bar[i] = '#';
        nosuspend {
            // hideCursor();
            printf("\r{s} {d: >3.0}%[{s}]", .{ activity, prog, bar });
            // showCursor();
        }
    }
};
