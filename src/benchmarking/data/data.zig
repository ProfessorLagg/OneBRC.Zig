const std = @import("std");

const cityNames = @embedFile("worldcities.txt");

pub fn readCityNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(allocator);

    var split_iter = std.mem.split(u8, cityNames[0..], "\n");
    var line: ?[]const u8 = split_iter.first();
    while (line != null) : (line = split_iter.next()) {
        if (line == null) {
            break;
        }
        try result.append(line.?);
    }

    return result;
}

/// Maps a value from the range fmin <= v <= fmax to the range tmin <= v <= tmax
fn map_float(comptime T: type, v: T, fmin: T, fmax: T, tmin: T, tmax: T) T {
    comptime {
        switch (@typeInfo(T)) {
            .Float, .ComptimeFloat => {},
            else => {
                @compileError("Expected floating point type, but found " ++ @typeName(T));
            },
        }
    }
    std.debug.assert(v >= fmin);
    std.debug.assert(v <= fmax);
    return tmin + ((tmax - tmin) / (fmax - fmin)) * (v - fmin);
}

// Generates random lines
pub fn generateLines(allocator: std.mem.Allocator, count: usize) !std.ArrayList([]const u8) {
    var cities: std.ArrayList([]const u8) = try readCityNames(allocator);
    defer cities.deinit();

    var rand_gen = std.rand.DefaultPrng.init(0);
    const rand = rand_gen.random();

    var result = std.ArrayList([]const u8).init(allocator);

    var buf: [128]u8 = undefined;
    for (0..count) |_| {
        // reset buffer
        @memset(buf[0..], @as(u8, '*'));
        // Generate line
        const key_idx: usize = rand.intRangeAtMost(usize, 0, cities.items.len - 1);
        const val: f64 = map_float(f64, rand.float(f64), 0.0, 1.0, -99.9, 99.9);
        const line: []u8 = try std.fmt.bufPrint(buf[0..], "{s};{d:.1}", .{ cities.items[key_idx], val });
        var aLine: []u8 = try allocator.alloc(u8, line.len);
        _ = &aLine;
        @memcpy(aLine, line);
        std.log.err("line: \"{s}\", aLine: \"{s}\" buf: \"{s}\"", .{ line, aLine, buf });

        // Copy line to output
        try result.append(aLine);
        allocator.free(aLine);
    }

    return result;
}
