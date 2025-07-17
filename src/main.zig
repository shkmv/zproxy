const std = @import("std");

pub fn main() !void {
    std.log.info("it's alive!", .{});
}

test "should fail" {
    try std.testing.expect(true);
}
