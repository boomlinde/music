const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

const Parser = @This();

tokenizer: *Tokenizer,

pub fn expect(self: Parser, comptime T: type) !T {
    return self.innerExpect(T, null);
}

pub fn expectWithStringAllocator(self: Parser, comptime T: type, string_allocator: std.mem.Allocator) !T {
    return self.innerExpect(T, string_allocator);
}

fn innerExpect(self: Parser, comptime T: type, string_allocator: ?std.mem.Allocator) !T {
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, try self.mustNext(), 0),
        .float => std.fmt.parseFloat(T, try self.mustNext()),
        .pointer => switch (T) {
            []u8 => {
                const token = try self.mustNext();
                return if (string_allocator) |a| a.dupe(u8, token) else token;
            },
            else => @compileError("unsupported slice/pointer type " ++ @typeName(T)),
        },
        .bool => {
            const token = try self.mustNext();
            return if (std.mem.eql(u8, token, "true"))
                true
            else if (std.mem.eql(u8, token, "false"))
                false
            else
                error.BadBoolValue;
        },
        .@"enum" => std.meta.stringToEnum(T, try self.mustNext()) orelse error.BadEnumValue,
        .@"struct" => self.expectStruct(T, string_allocator),
        else => @compileError("unsupported type"),
    };
}

fn expectStruct(self: Parser, comptime T: type, string_allocator: ?std.mem.Allocator) !T {
    var out: T = undefined;
    try self.expectLiteral("{");
    inline for (std.meta.fields(T)) |field| {
        const name = try self.expect([]u8);
        if (!std.mem.eql(u8, name, field.name)) return error.UnexpectedFieldName;
        try self.expectLiteral(":");
        const value = try self.innerExpect(field.type, string_allocator);
        @field(out, field.name) = value;
    }
    try self.expectLiteral("}");

    return out;
}

pub fn expectLiteral(self: Parser, literal: []const u8) !void {
    const token = try self.mustNext();
    if (!std.mem.eql(u8, token, literal)) return error.UnexpectedLiteral;
}

fn mustNext(self: Parser) ![]u8 {
    return try self.tokenizer.next() orelse error.ExpectedSomething;
}

test Parser {
    const t = std.testing;
    const T = struct {
        @"hello world": u8,
        b: i16,
        c: struct {
            x: f32,
            y: f64,
        },
    };
    var r = testStream("{ hello\\ world: 32 b: 64 c:{x: -1.3 y: 13 }}");
    var tokenbuf: [100]u8 = undefined;
    var tokenizer = Tokenizer{
        .reader = r.reader().any(),
        .buf = &tokenbuf,
    };
    const parser = Parser{ .tokenizer = &tokenizer };

    const v = try parser.expect(T);
    try t.expectEqual(v.@"hello world", 32);
    try t.expectEqual(v.b, 64);
    try t.expectEqual(v.c.x, -1.3);
    try t.expectEqual(v.c.y, 13);
}

fn testStream(str: []const u8) std.io.FixedBufferStream([]const u8) {
    return std.io.FixedBufferStream([]const u8){ .buffer = str, .pos = 0 };
}
