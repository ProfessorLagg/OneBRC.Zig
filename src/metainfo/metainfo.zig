const std = @import("std");
pub fn sumFieldSizes(comptime T: type) comptime_int {
    if (!@inComptime()) {
        @compileError("Function must be run at comptime");
    }

    const Ti: std.builtin.Type = @typeInfo(T);
    if (Ti != .@"struct") {
        @compileError("Can only sum the size of fields for structs. " ++ @typeName(T) ++ " is not a struct");
    }

    const field_count = Ti.@"struct".fields.len;

    var sum: comptime_int = 0;
    for (0..field_count) |field_index| {
        const field_info: std.builtin.Type.StructField = Ti.@"struct".fields[field_index];
        sum += @sizeOf(field_info.type);
    }
    return sum;
}
pub fn StructMemInfo(comptime T: type) type {
    const Ti: std.builtin.Type = comptime @typeInfo(T);
    const T_size = comptime @sizeOf(T);
    const T_align = comptime @alignOf(T);
    const T_fieldSize = comptime switch (Ti) {
        .@"struct" => sumFieldSizes(T),
        else => 0,
    };
    return struct {
        size: u32 = T_size,
        alignment: u32 = T_align,
        fieldSize: u32 = T_fieldSize,
        padding: u32 = T_size - T_fieldSize,
    };
}

pub fn getStructMemInfo(comptime T: type) StructMemInfo(T) {
    return .{};
}

pub fn logMemInfo(comptime T: type) void {
    std.debug.assert(@typeInfo(T) == .@"struct");
    const memInfo: StructMemInfo(T) = getStructMemInfo(T);

    const format_data = .{ @typeName(T), memInfo.size, memInfo.alignment, memInfo.fieldSize, memInfo.padding };
    const format_string = comptime "PADDING DETECTED!\n\ttype: {s}:\n\tsize: {d}\n\talignment: {d}\n\tsum of field sizes: {d}\n\tpadding: {d}";

    switch (memInfo.padding) {
        0 => std.log.info(format_string, format_data),
        else => std.log.warn(format_string, format_data),
    }
}
