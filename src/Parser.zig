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

pub fn serialize(d: anytype, w: std.io.AnyWriter) !void {
    const T = @TypeOf(d);
    switch (@typeInfo(T)) {
        .int => try w.print("{} ", .{d}),
        .float => try w.print("{d} ", .{d}),
        .pointer => switch (T) {
            []u8 => {
                try w.print("\"", .{});
                for (d) |char| switch (char) {
                    '\\' => try w.print("\\\\", .{}),
                    '\"' => try w.print("\\\"", .{}),
                    else => try w.writeByte(char),
                };
                try w.print("\" ", .{});
            },
            else => @compileError("unsupported slice/pointer type " ++ @typeName(T)),
        },
        .bool => try w.print("{s} ", .{if (d) "true" else "false"}),
        .@"enum" => try w.print("{s} ", .{enumString(d)}),
        .@"struct" => {
            try w.print("{{ ", .{});
            inline for (std.meta.fields(T)) |f| {
                try w.print("{s}: ", .{f.name});
                try serialize(@field(d, f.name), w);
            }
            try w.print("}} ", .{});
        },
        .array => {
            try w.print("[ ", .{});
            for (d) |v| try serialize(v, w);
            try w.print("] ", .{});
        },
        else => @compileError("unsupported type"),
    }
}

fn enumString(v: anytype) []u8 {
    inline for (std.meta.fields(@TypeOf(v))) |f| {
        if (f.value == v) return f.name;
    }
    return error.BadEnumValue;
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
        .array => |ainfo| arrblk: {
            var out: [ainfo.len]ainfo.child = undefined;
            try self.expectLiteral("[");
            for (0..ainfo.len) |i| {
                out[i] = try self.innerExpect(ainfo.child, string_allocator);
            }
            try self.expectLiteral("]");
            break :arrblk out;
        },
        else => @compileError("unsupported type"),
    };
}

fn expectStruct(self: Parser, comptime T: type, string_allocator: ?std.mem.Allocator) !T {
    var out: T = .{};
    try self.expectLiteral("{");
    fieldloop: while (true) {
        const name_or_end = try self.expect([]u8);
        if (std.mem.eql(u8, name_or_end, "}")) break;

        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, name_or_end, field.name)) {
                try self.expectLiteral(":");
                const value = try self.innerExpect(field.type, string_allocator);
                @field(out, field.name) = value;
                continue :fieldloop;
            }
        }

        return error.UnknownStructFieldName;
    }

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
    const teststr = "{ hello: 32 b: 64 c: { x: -1.3 y: 13 } x: [ 1 2 3 ] } ";
    const t = std.testing;
    const T = struct {
        hello: u8 = 0,
        b: i16 = 1,
        c: struct {
            x: f32 = 2,
            y: f64 = 3,
        } = .{},
        x: [3]i8 = .{ 4, 5, 6 },
    };
    var r = testStream(teststr);
    var tokenbuf: [100]u8 = undefined;
    var tokenizer = Tokenizer{
        .reader = r.reader().any(),
        .buf = &tokenbuf,
    };
    const parser = Parser{ .tokenizer = &tokenizer };

    const v = try parser.expect(T);
    try t.expectEqual(v.hello, 32);
    try t.expectEqual(v.b, 64);
    try t.expectEqual(v.c.x, -1.3);
    try t.expectEqual(v.c.y, 13);
    try t.expectEqual([3]i8{ 1, 2, 3 }, v.x);

    // Serialize
    var wrbuf: [256]u8 = undefined;
    var w = std.io.FixedBufferStream([]u8){ .buffer = &wrbuf, .pos = 0 };
    try serialize(v, w.writer().any());
    const out = wrbuf[0..w.pos];
    try t.expectEqualStrings(teststr, out);
}

fn testStream(str: []const u8) std.io.FixedBufferStream([]const u8) {
    return std.io.FixedBufferStream([]const u8){ .buffer = str, .pos = 0 };
}
