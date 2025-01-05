const std = @import("std");

const PeekReader = @This();

r: std.io.AnyReader,
buf: ?u8 = null,

pub fn read(self: *PeekReader, buffer: []u8) anyerror!usize {
    if (buffer.len == 0) return 0;
    var idx: usize = 0;

    if (self.buf) |b| {
        self.buf = null;
        buffer[0] = b;
        idx += 1;
    }

    idx += try self.r.read(buffer[idx..]);
    return idx;
}

pub fn peek(self: *PeekReader) !?u8 {
    if (self.buf) |b| return b;

    var buf = [1]u8{undefined};
    const n = try self.r.read(&buf);
    if (n != 1) return null;
    self.buf = buf[0];
    return buf[0];
}

pub fn drop(self: *PeekReader) !void {
    if (self.buf == null) return error.DropWithoutPeek;
    self.buf = null;
}

pub fn reader(self: *PeekReader) std.io.GenericReader(*@This(), anyerror, read) {
    return .{ .context = self };
}

test PeekReader {
    const t = std.testing;
    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = "abc1def2",
    };
    var pr = PeekReader{ .r = stream.reader().any() };
    const r = pr.reader().any();

    var n: usize = undefined;

    var buf: [4]u8 = undefined;

    n = try r.read(&buf);
    try t.expectEqual(4, n);
    try t.expectEqualStrings("abc1", &buf);

    try t.expectEqual('d', try pr.peek() orelse 0);
    try t.expectEqual('d', try pr.peek() orelse 0);

    n = try r.read(&buf);
    try t.expectEqual(4, n);
    try t.expectEqualStrings("def2", &buf);
}
