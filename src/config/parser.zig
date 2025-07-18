const std = @import("std");
const types = @import("types.zig");

pub const ParseError = error{
    UnexpectedCharacter,
    UnexpectedEndOfInput,
    InvalidIndentation,
    InvalidYamlFormat,
    KeyNotFound,
    ValueTypeMismatch,
    ArrayIndexOutOfBounds,
};

pub fn Parser(comptime T: type) type {
    return struct {
        source: []const u8,
        pos: usize,
        line: usize,
        column: usize,

        const Self = @This();

        pub fn init(source: []const u8) Self {
            return Self{
                .source = source,
                .pos = 0,
                .line = 1,
                .column = 1,
            };
        }

        pub fn parse(self: *Self) ParseError!T {
            self.skip_whitespace();
            if (self.pos >= self.source.len) {
                return T{};
            }
            const result = self.parse_value(T, 0);
            return result;
        }

        fn parse_value(self: *Self, comptime ValueType: type, indent_level: usize) ParseError!ValueType {
            self.skip_whitespace();

            if (self.pos >= self.source.len) {
                return ParseError.UnexpectedEndOfInput;
            }

            const type_info = @typeInfo(ValueType);

            switch (type_info) {
                .bool => return self.parse_bool(),
                .int => return self.parse_int(ValueType),
                .float => return self.parse_float(ValueType),
                .array => |array_info| {
                    return self.parse_array(ValueType, array_info, indent_level);
                },
                .@"struct" => |struct_info| {
                    return self.parse_struct(ValueType, struct_info, indent_level);
                },
                .optional => |optional_info| {
                    if (self.match_keyword("null")) {
                        return null;
                    }
                    return try self.parse_value(optional_info.child, indent_level);
                },
                .pointer => |ptr_info| {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        return self.parse_string();
                    }
                    @compileError("Unsupported pointer type");
                },
                else => @compileError("Unsupported type: " ++ @typeName(ValueType)),
            }
        }

        fn parse_bool(self: *Self) ParseError!bool {
            if (self.match_keyword("true")) {
                return true;
            } else if (self.match_keyword("false")) {
                return false;
            }
            return ParseError.ValueTypeMismatch;
        }

        fn parse_int(self: *Self, comptime IntType: type) ParseError!IntType {
            const start = self.pos;

            if (self.pos < self.source.len and
                (self.source[self.pos] == '+' or self.source[self.pos] == '-'))
            {
                self.pos += 1;
            }

            while (self.pos < self.source.len and
                self.source[self.pos] >= '0' and
                self.source[self.pos] <= '9')
            {
                self.pos += 1;
            }

            if (start == self.pos or (start + 1 == self.pos and (self.source[start] == '+' or self.source[start] == '-'))) {
                return ParseError.ValueTypeMismatch;
            }

            const text = self.source[start..self.pos];
            return std.fmt.parseInt(IntType, text, 10) catch ParseError.ValueTypeMismatch;
        }

        fn parse_float(self: *Self, comptime FloatType: type) ParseError!FloatType {
            const start = self.pos;

            if (self.pos < self.source.len and
                (self.source[self.pos] == '+' or self.source[self.pos] == '-'))
            {
                self.pos += 1;
            }

            var has_dot = false;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (ch >= '0' and ch <= '9') {
                    self.pos += 1;
                } else if (ch == '.' and !has_dot) {
                    has_dot = true;
                    self.pos += 1;
                } else {
                    break;
                }
            }

            if (start == self.pos or (start + 1 == self.pos and (self.source[start] == '+' or self.source[start] == '-'))) {
                return ParseError.ValueTypeMismatch;
            }

            const text = self.source[start..self.pos];
            return std.fmt.parseFloat(FloatType, text) catch ParseError.ValueTypeMismatch;
        }

        fn parse_string(self: *Self) ParseError![]const u8 {
            self.skip_whitespace();

            if (self.pos >= self.source.len) {
                return "";
            }

            if (self.source[self.pos] == '"' or self.source[self.pos] == '\'') {
                const quote_char = self.source[self.pos];
                self.pos += 1;

                const start = self.pos;

                while (self.pos < self.source.len and self.source[self.pos] != quote_char) {
                    if (self.source[self.pos] == '\\') {
                        self.pos += 1;
                        if (self.pos >= self.source.len) {
                            return ParseError.UnexpectedEndOfInput;
                        }
                    }
                    self.pos += 1;
                }

                if (self.pos >= self.source.len) {
                    return ParseError.UnexpectedEndOfInput;
                }

                const content = self.source[start..self.pos];
                self.pos += 1;

                return content;
            }

            const start = self.pos;
            while (self.pos < self.source.len and
                self.source[self.pos] != '\n' and
                self.source[self.pos] != '\r' and
                self.source[self.pos] != ':' and
                self.source[self.pos] != '#' and
                self.source[self.pos] != ',' and
                self.source[self.pos] != ']')
            {
                self.pos += 1;
            }

            const trimmed = std.mem.trim(u8, self.source[start..self.pos], " \t");
            return if (trimmed.len == 0) "" else trimmed;
        }

        fn parse_array(self: *Self, comptime ArrayType: type, comptime array_info: std.builtin.Type.Array, indent_level: usize) ParseError!ArrayType {
            var result: ArrayType = std.mem.zeroes(ArrayType);

            var index: usize = 0;

            self.skip_whitespace();
            const is_yaml_list = self.pos < self.source.len and self.source[self.pos] == '-';

            if (is_yaml_list) {
                while (self.pos < self.source.len and index < array_info.len) {
                    self.skip_whitespace();
                    self.skip_empty_lines();

                    if (self.pos >= self.source.len) break;

                    const current_indent = self.get_current_indent();
                    if (current_indent < indent_level) break;

                    if (self.source[self.pos] == '-' and
                        self.pos + 1 < self.source.len and
                        (self.source[self.pos + 1] == ' ' or self.source[self.pos + 1] == '\n'))
                    {
                        self.pos += 1;
                        self.skip_whitespace();

                        const item_indent = self.get_current_indent();
                        result[index] = try self.parse_value(array_info.child, item_indent);
                        index += 1;
                    } else {
                        break;
                    }
                }
            } else {
                if (self.pos < self.source.len and self.source[self.pos] == '[') {
                    self.pos += 1;

                    while (self.pos < self.source.len and index < array_info.len) {
                        self.skip_whitespace();

                        if (self.pos >= self.source.len or self.source[self.pos] == ']') {
                            break;
                        }

                        result[index] = try self.parse_value(array_info.child, indent_level);
                        index += 1;

                        self.skip_whitespace();
                        if (self.pos < self.source.len and self.source[self.pos] == ',') {
                            self.pos += 1;
                        } else {
                            break;
                        }
                    }

                    if (self.pos < self.source.len and self.source[self.pos] == ']') {
                        self.pos += 1;
                    }
                }
            }

            return result;
        }

        fn parse_struct(self: *Self, comptime StructType: type, comptime struct_info: std.builtin.Type.Struct, indent_level: usize) ParseError!StructType {
            var result: StructType = StructType{};

            while (self.pos < self.source.len) {
                self.skip_whitespace();
                self.skip_empty_lines();

                if (self.pos >= self.source.len) break;

                const current_indent = self.get_current_indent();
                if (current_indent < indent_level) break;

                const key = try self.parse_key();
                if (key.len == 0) break;

                self.skip_whitespace();
                if (self.pos >= self.source.len or self.source[self.pos] != ':') {
                    return ParseError.InvalidYamlFormat;
                }
                self.pos += 1;

                var field_found = false;
                inline for (struct_info.fields) |field| {
                    if (std.mem.eql(u8, key, field.name)) {
                        self.skip_whitespace();

                        if (self.pos < self.source.len and
                            self.source[self.pos] != '\n' and
                            self.source[self.pos] != '\r')
                        {
                            @field(result, field.name) = try self.parse_value(field.type, current_indent + 1);
                        } else {
                            self.skip_to_next_line();
                            @field(result, field.name) = try self.parse_value(field.type, current_indent + 2);
                        }
                        field_found = true;
                        break;
                    }
                }

                if (!field_found) {
                    self.skip_to_end_of_structure(current_indent);
                    continue;
                }
            }

            return result;
        }

        fn parse_key(self: *Self) ParseError![]const u8 {
            const start = self.pos;

            while (self.pos < self.source.len and
                self.source[self.pos] != ':' and
                self.source[self.pos] != '\n' and
                self.source[self.pos] != '\r')
            {
                self.pos += 1;
            }

            return std.mem.trim(u8, self.source[start..self.pos], " \t");
        }

        fn match_keyword(self: *Self, keyword: []const u8) bool {
            if (self.pos + keyword.len > self.source.len) return false;

            const slice = self.source[self.pos .. self.pos + keyword.len];
            if (std.mem.eql(u8, slice, keyword)) {
                if (self.pos + keyword.len < self.source.len) {
                    const next_ch = self.source[self.pos + keyword.len];
                    if (next_ch != ' ' and next_ch != '\t' and next_ch != '\n' and
                        next_ch != '\r' and next_ch != ':' and next_ch != '#')
                    {
                        return false;
                    }
                }
                self.pos += keyword.len;
                return true;
            }

            return false;
        }

        fn get_current_indent(self: *Self) usize {
            var indent: usize = 0;
            var temp_pos = self.pos;

            while (temp_pos > 0 and self.source[temp_pos - 1] != '\n') {
                temp_pos -= 1;
            }

            while (temp_pos < self.source.len and self.source[temp_pos] == ' ') {
                indent += 1;
                temp_pos += 1;
            }

            return indent;
        }

        fn skip_whitespace(self: *Self) void {
            while (self.pos < self.source.len and
                (self.source[self.pos] == ' ' or self.source[self.pos] == '\t'))
            {
                if (self.source[self.pos] == '\t') {
                    self.column += 4;
                } else {
                    self.column += 1;
                }
                self.pos += 1;
            }
        }

        fn skip_to_next_line(self: *Self) void {
            while (self.pos < self.source.len and
                self.source[self.pos] != '\n' and
                self.source[self.pos] != '\r')
            {
                self.pos += 1;
            }

            if (self.pos < self.source.len) {
                if (self.source[self.pos] == '\r' and
                    self.pos + 1 < self.source.len and
                    self.source[self.pos + 1] == '\n')
                {
                    self.pos += 2;
                } else {
                    self.pos += 1;
                }
                self.line += 1;
                self.column = 1;
            }
        }

        fn skip_empty_lines(self: *Self) void {
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (ch == '\n' or ch == '\r') {
                    self.skip_to_next_line();
                    self.skip_whitespace();
                } else {
                    break;
                }
            }
        }

        fn skip_to_end_of_structure(self: *Self, base_indent: usize) void {
            while (self.pos < self.source.len) {
                self.skip_to_next_line();
                self.skip_whitespace();

                if (self.pos >= self.source.len) break;

                const current_indent = self.get_current_indent();
                if (current_indent <= base_indent) {
                    break;
                }
            }
        }
    };
}

pub fn parse_config(yaml_content: []const u8) ParseError!types.Config {
    var parser = Parser(types.Config).init(yaml_content);
    return parser.parse();
}

const testing = std.testing;

test "simple parsing test" {
    const simple_yaml = "name: test";

    const SimpleConfig = struct {
        name: []const u8 = "",
    };

    var parser = Parser(SimpleConfig).init(simple_yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("test", result.name);
}

test "parse single route" {
    const route_yaml =
        \\pattern: "/api/*"
        \\load_balancer: "round_robin"
    ;

    const TestRoute = struct {
        pattern: []const u8 = "",
        load_balancer: []const u8 = "",
    };

    var parser = Parser(TestRoute).init(route_yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("/api/*", result.pattern);
    try testing.expectEqualStrings("round_robin", result.load_balancer);
}

test "parse simple route array" {
    const yaml =
        \\routes:
        \\  - pattern: "/api/*"
    ;

    const config = try parse_config(yaml);
    try testing.expectEqualStrings("/api/*", config.routes[0].pattern);
}

test "parse basic config" {
    const yaml =
        \\name: "ZProxy"
        \\version: "1.0.0"
        \\port: 8080
        \\debug: true
        \\timeout: 30.5
    ;

    const config = try parse_config(yaml);
    try testing.expectEqualStrings("ZProxy", config.name);
    try testing.expectEqualStrings("1.0.0", config.version);
    try testing.expectEqual(@as(u16, 8080), config.port);
    try testing.expectEqual(true, config.debug);
    try testing.expectEqual(@as(?f32, 30.5), config.timeout);
}

test "parse config with defaults" {
    const yaml = "name: TestProxy";
    const config = try parse_config(yaml);

    try testing.expectEqualStrings("TestProxy", config.name);
    try testing.expectEqualStrings("", config.version);
    try testing.expectEqual(@as(u16, 8080), config.port);
    try testing.expectEqual(false, config.debug);
    try testing.expectEqual(@as(?f32, null), config.timeout);
}

test "parse empty config" {
    const yaml = "";
    const config = try parse_config(yaml);

    try testing.expectEqualStrings("", config.name);
    try testing.expectEqual(@as(u16, 8080), config.port);
    try testing.expectEqual(false, config.debug);
}

test "parse quoted strings" {
    const yaml =
        \\name: "Test with spaces"
        \\version: 'Single quotes'
    ;

    const TestConfig = struct {
        name: []const u8 = "",
        version: []const u8 = "",
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("Test with spaces", result.name);
    try testing.expectEqualStrings("Single quotes", result.version);
}

test "parse boolean values" {
    const yaml =
        \\enabled: true
        \\disabled: false
    ;

    const TestConfig = struct {
        enabled: bool = false,
        disabled: bool = true,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(true, result.enabled);
    try testing.expectEqual(false, result.disabled);
}

test "parse integer values" {
    const yaml =
        \\port: 8080
        \\negative: -42
        \\positive: +100
    ;

    const TestConfig = struct {
        port: u16 = 0,
        negative: i32 = 0,
        positive: i32 = 0,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(@as(u16, 8080), result.port);
    try testing.expectEqual(@as(i32, -42), result.negative);
    try testing.expectEqual(@as(i32, 100), result.positive);
}

test "parse float values" {
    const yaml =
        \\timeout: 30.5
        \\rate: -1.25
        \\percentage: +99.9
    ;

    const TestConfig = struct {
        timeout: f32 = 0.0,
        rate: f32 = 0.0,
        percentage: f32 = 0.0,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(@as(f32, 30.5), result.timeout);
    try testing.expectEqual(@as(f32, -1.25), result.rate);
    try testing.expectEqual(@as(f32, 99.9), result.percentage);
}

test "parse optional values" {
    const yaml =
        \\timeout: 30.5
        \\retries: null
    ;

    const TestConfig = struct {
        timeout: ?f32 = null,
        retries: ?i32 = null,
        missing: ?[]const u8 = null,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(@as(?f32, 30.5), result.timeout);
    try testing.expectEqual(@as(?i32, null), result.retries);
    try testing.expectEqual(@as(?[]const u8, null), result.missing);
}

test "parse inline arrays" {
    const yaml = "ports: [8080, 8081, 8082]";

    const TestConfig = struct {
        ports: [3]u16 = [_]u16{0} ** 3,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(@as(u16, 8080), result.ports[0]);
    try testing.expectEqual(@as(u16, 8081), result.ports[1]);
    try testing.expectEqual(@as(u16, 8082), result.ports[2]);
}

test "parse yaml list arrays" {
    const yaml =
        \\ports:
        \\  - 8080
        \\  - 8081
        \\  - 8082
    ;

    const TestConfig = struct {
        ports: [3]u16 = [_]u16{0} ** 3,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqual(@as(u16, 8080), result.ports[0]);
    try testing.expectEqual(@as(u16, 8081), result.ports[1]);
    try testing.expectEqual(@as(u16, 8082), result.ports[2]);
}

test "parse nested structs" {
    const yaml =
        \\database:
        \\  host: "localhost"
        \\  port: 5432
        \\  enabled: true
    ;

    const Database = struct {
        host: []const u8 = "",
        port: u16 = 0,
        enabled: bool = false,
    };

    const TestConfig = struct {
        database: Database = Database{},
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("localhost", result.database.host);
    try testing.expectEqual(@as(u16, 5432), result.database.port);
    try testing.expectEqual(true, result.database.enabled);
}

test "parse with unknown fields" {
    const yaml =
        \\name: "test"
        \\unknown_field: "ignored"
        \\port: 8080
    ;

    const TestConfig = struct {
        name: []const u8 = "",
        port: u16 = 0,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("test", result.name);
    try testing.expectEqual(@as(u16, 8080), result.port);
}

test "parse multiline values" {
    const yaml =
        \\name: "test"
        \\
        \\port: 8080
        \\
        \\debug: true
    ;

    const TestConfig = struct {
        name: []const u8 = "",
        port: u16 = 0,
        debug: bool = false,
    };

    var parser = Parser(TestConfig).init(yaml);
    const result = try parser.parse();

    try testing.expectEqualStrings("test", result.name);
    try testing.expectEqual(@as(u16, 8080), result.port);
    try testing.expectEqual(true, result.debug);
}

test "parse error cases" {
    const invalid_yaml = "name: test\nport: not_a_number";

    const TestConfig = struct {
        name: []const u8 = "",
        port: u16 = 0,
    };

    var parser = Parser(TestConfig).init(invalid_yaml);
    try testing.expectError(ParseError.ValueTypeMismatch, parser.parse());
}

test "parse error invalid yaml format" {
    const invalid_yaml = "name test";

    const TestConfig = struct {
        name: []const u8 = "",
    };

    var parser = Parser(TestConfig).init(invalid_yaml);
    try testing.expectError(ParseError.InvalidYamlFormat, parser.parse());
}
