const std = @import("std");
const parser = @import("parser.zig");
const types = @import("types.zig");

pub fn config_from_file(file_path: []const u8) parser.ParserError!types.Config {
    std.log.info("load config from file: {s}", .{file_path});
    return error.InvalidFormat;
}

