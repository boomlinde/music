const std = @import("std");

pub fn decode(r: std.io.AnyReader) !u28 {
    var count: u8 = 0;
    var out: u28 = 0;

    while (true) {
        if (count == 4) return error.TooLongVLQ;
        out <<= 7;
        const b = try r.readByte();
        out |= (b & 0x7f);
        if ((b & 0x80) == 0) break;
        count += 1;
    }

    return out;
}

pub fn encode(w: std.io.AnyWriter, value: u28) !void {
    var v: u28 = value;
    var s = Stack(u8, 4){};
    while (true) {
        try s.push(@intCast(v & 0x7f));
        v >>= 7;
        if (v == 0) break;
    }

    while (s.len != 0) {
        const continued: u8 = if (s.len > 1) 0x80 else 0;
        const out = continued | try s.pop();
        _ = try w.write(@as(*const [1]u8, @ptrCast(&out)));
    }
}

const VLQTestCase = struct {
    number: u28,
    representation: []const u8,
};

// Example cases from the SMF specification
const vlq_test_cases = [_]VLQTestCase{
    .{ .number = 0x00, .representation = &.{0x00} },
    .{ .number = 0x40, .representation = &.{0x40} },
    .{ .number = 0x80, .representation = &.{ 0x81, 0x00 } },
    .{ .number = 0x2000, .representation = &.{ 0xc0, 0x00 } },
    .{ .number = 0x3fff, .representation = &.{ 0xff, 0x7f } },
    .{ .number = 0x4000, .representation = &.{ 0x81, 0x80, 0x00 } },
    .{ .number = 0x100000, .representation = &.{ 0xc0, 0x80, 0x00 } },
    .{ .number = 0x1fffff, .representation = &.{ 0xff, 0xff, 0x7f } },
    .{ .number = 0x200000, .representation = &.{ 0x81, 0x80, 0x80, 0x00 } },
    .{ .number = 0x8000000, .representation = &.{ 0xc0, 0x80, 0x80, 0x00 } },
    .{ .number = 0xfffffff, .representation = &.{ 0xff, 0xff, 0xff, 0x7f } },
};

test encode {
    for (vlq_test_cases) |case| {
        var buf: [5]u8 = undefined;
        var stream = std.io.FixedBufferStream([]u8){
            .pos = 0,
            .buffer = &buf,
        };

        try encode(stream.writer().any(), case.number);
        try std.testing.expectEqualSlices(u8, case.representation, buf[0..stream.pos]);
    }
}

test decode {
    for (vlq_test_cases) |case| {
        var stream = std.io.FixedBufferStream([]const u8){
            .pos = 0,
            .buffer = case.representation,
        };
        const given = try decode(stream.reader().any());

        try std.testing.expectEqual(case.number, given);
    }

    // Test the case of a too long VLQ: it should be a maximum of 4 bytes even if the format in principle could represent any arbitrary length value
    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = &.{ 0xff, 0xff, 0xff, 0xff, 0x7f },
    };

    try std.testing.expectError(error.TooLongVLQ, decode(stream.reader().any()));
}

fn Stack(comptime T: type, comptime size: comptime_int) type {
    return struct {
        buf: [size]T = undefined,
        len: std.math.IntFittingRange(0, size) = 0,

        fn push(self: *@This(), value: T) !void {
            if (self.len == self.buf.len) return error.StackOverflow;
            self.buf[self.len] = value;
            self.len += 1;
        }

        fn pop(self: *@This()) !T {
            if (self.len == 0) return error.StackUnderflow;
            self.len -= 1;
            return self.buf[self.len];
        }
    };
}
