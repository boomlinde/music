pub fn List(comptime T: type) type {
    return struct {
        const L = @This();
        pub const Link = struct {
            value: T,
            back: ?*Link = null,
            front: ?*Link = null,
        };

        front: ?*Link = null,
        back: ?*Link = null,

        pub fn clear(self: *L) void {
            while (self.front) |front| self.unlink(front);
        }

        pub fn pushFront(self: *L, item: *Link) void {
            const old_front = self.front;
            self.front = item;
            item.front = null;
            item.back = old_front;
            if (old_front) |f| f.front = item;
            if (self.back == null) self.back = item;
        }

        pub fn pushBack(self: *L, item: *Link) void {
            const old_back = self.back;
            self.back = item;
            item.front = old_back;
            item.back = null;
            if (old_back) |b| b.back = item;
            if (self.front == null) self.front = item;
        }

        pub fn unlink(self: *L, item: *Link) void {
            if (item.front) |front|
                front.back = item.back
            else
                self.front = item.back;

            if (item.back) |back|
                back.front = item.front
            else
                self.back = item.front;

            item.front = null;
            item.back = null;
        }

        pub fn popFront(self: *L) ?*Link {
            if (self.front) |front| {
                self.unlink(front);
                return front;
            }
            return null;
        }

        pub fn popBack(self: *L) ?*Link {
            if (self.back) |back| {
                self.unlink(back);
                return back;
            }
            return null;
        }
    };
}

test List {
    const t = @import("std").testing;
    var l = List(u8){};
    var a = List(u8).Link{ .value = 1 };
    var b = List(u8).Link{ .value = 2 };

    l.pushFront(&a);
    try t.expectEqual(&a, l.front);
    try t.expectEqual(&a, l.back);
    try t.expectEqual(null, a.front);
    try t.expectEqual(null, a.back);
    l.pushFront(&b);
    try t.expectEqual(&b, l.front);
    try t.expectEqual(&a, l.back);
    try t.expectEqual(&a, b.back);
    try t.expectEqual(null, b.front);
    try t.expectEqual(&b, a.front);
    try t.expectEqual(null, a.back);
    l.unlink(&b);
    try t.expectEqual(&a, l.front);
    try t.expectEqual(&a, l.back);
    try t.expectEqual(null, a.front);
    try t.expectEqual(null, a.back);
    l.unlink(&a);
    try t.expectEqual(null, l.front);
    try t.expectEqual(null, l.back);
}
