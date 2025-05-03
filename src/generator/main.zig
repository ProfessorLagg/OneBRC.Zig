const builtin = @import("builtin");
const std = @import("std");
const CityNames = @import("worldcities.zig").CityNames;

pub const std_options: std.Options = .{
    // Set the log level to info to .debug. use the scope levels instead
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseSmall => .info,
        .ReleaseFast => .err,
    },
    .log_scope_levels = &[_]std.log.ScopeLevel{},
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

var stdout: std.io.AnyWriter = undefined;
var stderr: std.io.AnyWriter = undefined;

const mantxt = @embedFile("man.txt");
pub fn main() !void {
    init();
    defer deinit();

    const options: GenOptions = GenOptions catch |err| {
        printErr(stderr, "Could not parse args:", err, @errorReturnTrace());
    };
}

fn printErr(writer: std.io.AnyWriter, msg: []const u8, err: anyerror, stack_trace: ?*std.builtin.StackTrace) noreturn {
    const include_trace: bool = comptime switch (builtin.mode) {
        .Debug => true,
        else => false,
    };
    const trace: ?*std.builtin.StackTrace = if (include_trace) {
        stack_trace;
    } else {
        null;
    };
    std.fmt.format(writer, "{s}\n{any}{any}\n{s}", .{ msg, err, trace, mantxt });
}

fn init() void {
    allocator = gpa.allocator();
    stdout = std.io.getStdOut().writer();
    stderr = std.io.getStdErr().writer();
}
fn deinit() void {
    _ = gpa.deinit();
}

const GenOptions = struct {
    num_lines: usize,
    output_path: []const u8,

    const ParseCliError = error{
        TooFewArguments,
        TooManyArguments,
    };
    pub fn parseCLI() !GenOptions {
        var base_args = std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, base_args);

        const args = base_args[1..];
        if (args.len < 2) return ParseCliError.TooFewArguments;
        if (args.len > 2) return ParseCliError.TooManyArguments;
    }

    pub fn deinit(self: *GenOptions) void {
        allocator.free(self.output_path);
    }
};

const LineGenerator = struct {
    const TPrng = std.Random.DefaultPrng;

    buffer: [128]u8 = undefined,
    lines_left: usize,

    prng: TPrng = undefined,
    rand: std.Random = undefined,

    pub fn initSeeded(line_count: usize, seed: u64) LineGenerator {
        var r = LineGenerator{};

        r.lines_left = line_count;

        r.prng = std.Random.DefaultPrng.init(seed);
        r.rand = r.prng.random();
        return r;
    }

    pub fn next(self: *LineGenerator) ?[]const u8 {
        if (self.lines_left == 0) return null;
        @memset(self.buffer[0..], 0);
        const name_idx = self.rand.int(usize) % CityNames.len;
        const name = CityNames[name_idx];
        // TODO finish this

    }
};
