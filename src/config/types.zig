const std = @import("std");

const ConfigError = error{
    RoutePatternTooLong,
};

pub const Config = struct {
    name: []const u8 = "",
    version: []const u8 = "",
    port: u16 = 8080,
    debug: bool = false,
    timeout: ?f32 = null,
    routes: [64]Route = [_]Route{Route{}} ** 64,
};

pub const Route = struct {
    pattern: []const u8 = "",
    backends: [3]Backend = [_]Backend{Backend{}} ** 3,
    load_balancer: []const u8 = "",
    health_check: HealthCheck = HealthCheck{},
};

pub const Backend = struct {
    address: []const u8 = "",
};

pub const HealthCheck = struct {
    interval: []const u8 = "",
    timeout: []const u8 = "",
};
