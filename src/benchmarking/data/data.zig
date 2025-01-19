const std = @import("std");

const cityNames = @embedFile("worldcities.txt");

pub fn allocReadCityNames(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
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