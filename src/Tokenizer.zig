const std = @import("std");

const Tokenizer = @This();

reader: std.io.AnyReader,
buf: []u8,
n: usize = 0,
again: ?u8 = null,
mode: enum {
    normal,
    normal_escaped,
    string,
    string_escaped,
    comment,
} = .normal,

fn append(self: *Tokenizer, ch: u8) !void {
    if (self.n >= self.buf.len) return error.TokenTooLong;

    self.buf[self.n] = ch;
    self.n += 1;
}

fn emit(self: *Tokenizer) ?[]u8 {
    defer self.n = 0;
    if (self.n == 0) return null;
    return self.buf[0..self.n];
}

fn consume(self: *Tokenizer, ch: u8) !?[]u8 {
    switch (self.mode) {
        .normal => switch (ch) {
            '\n', '\r', ' ', '\t' => return self.emit(),
            '{', '}', ':', '[', ']' => {
                if (self.n > 0)
                    self.again = ch
                else
                    try self.append(ch);
                return self.emit();
            },
            '#' => {
                if (self.n > 0) {
                    self.again = ch;
                    return self.emit();
                }
                self.mode = .comment;
            },
            '\\' => self.mode = .normal_escaped,
            '"' => self.mode = .string,
            else => try self.append(ch),
        },
        .normal_escaped => {
            try self.append(ch);
            self.mode = .normal;
        },
        .string => switch (ch) {
            '"' => {
                defer self.mode = .normal;
                return self.emit();
            },
            '\\' => self.mode = .string_escaped,
            else => try self.append(ch),
        },
        .string_escaped => {
            try self.append(ch);
            self.mode = .string;
        },
        .comment => if (ch == '\n') {
            self.mode = .normal;
        },
    }
    return null;
}

fn nextByte(self: *Tokenizer) !?u8 {
    if (self.again) |peeked| {
        self.again = null;
        return peeked;
    }
    var ch: [1]u8 = undefined;
    const nread = try self.reader.read(&ch);
    if (nread == 0) return null;
    return ch[0];
}

pub fn next(self: *Tokenizer) !?[]u8 {
    while (try self.nextByte()) |ch| {
        if (try self.consume(ch)) |token| {
            return token;
        }
    }
    return try self.consume('\n');
}

test "Tokenizer" {
    var stream = testStream("{a\\ x: 10 b: \"hejsan \\\"hoppsan\\\"\"}");

    var tokenbuf: [32]u8 = undefined;
    var t = Tokenizer{
        .reader = stream.reader().any(),
        .buf = &tokenbuf,
    };

    const expected = [_][]const u8{
        "{", "a x", ":", "10", "b", ":", "hejsan \"hoppsan\"", "}",
    };

    var i: usize = 0;
    while (try t.next()) |token| {
        try std.testing.expectEqualStrings(expected[i], token);
        i += 1;
    }
    try std.testing.expect(i == expected.len);
}

fn testStream(str: []const u8) std.io.FixedBufferStream([]const u8) {
    return std.io.FixedBufferStream([]const u8){ .buffer = str, .pos = 0 };
}
