const std = @import("std");

const ConfigError = error{
    RoutePatternTooLong,
};

pub const Config = struct {
    const MAX_ROUTES = 64;

    listen_port: u16 = 80,
    max_connections: u32 = 1000,
    routes: [MAX_ROUTES]Route = [_]Route{Route{}} ** MAX_ROUTES,
};

pub const Route = struct {
    const MAX_PATTERN_LENGTH = 255;

    pattern_buffer: [MAX_PATTERN_LENGTH + 1]u8 = [_]u8{0} ** (MAX_PATTERN_LENGTH + 1),
    pattern_len: u8 = 0,

    const Self = @This();

    pub fn pattern(self: *const Self) []const u8 {
        return self.pattern_buffer[0..self.pattern_len];
    }

    pub fn set_pattern(self: *Self, pat: []const u8) ConfigError!void {
        if (pat.len > self.pattern_buffer.len) {
            return error.RoutePatternTooLong;
        }

        @memcpy(self.pattern_buffer[0..pat.len], pat);
        self.pattern_len = @intCast(pat.len);
    }
};

const testing = std.testing;

test "[Route] set/get pattern" {
    var route = Route{};

    const pattern = "/api/v1/*";
    try route.set_pattern(pattern);
    try testing.expect(route.pattern_len == pattern.len);

    const stored_pattern = route.pattern();
    try testing.expectEqualSlices(u8, pattern, stored_pattern);

    // get error
    const long_pattern: [257]u8 = [_]u8{'a'} ** 257;
    route.set_pattern(&long_pattern) catch |err| {
        try testing.expect(err == ConfigError.RoutePatternTooLong);
    };
}
