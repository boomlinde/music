pub fn match(pattern: []const u8, name: []const u8) bool {
    var px: usize = 0;
    var nx: usize = 0;
    var nextPx: usize = 0;
    var nextNx: usize = 0;

    while (px < pattern.len or nx < name.len) {
        if (px < pattern.len) {
            const c = pattern[px];
            switch (c) {
                '?' => if (nx < name.len) {
                    px += 1;
                    nx += 1;
                    continue;
                },
                '*' => {
                    nextPx = px;
                    nextNx = nx + 1;
                    px += 1;
                    continue;
                },
                else => if (nx < name.len and name[nx] == c) {
                    px += 1;
                    nx += 1;
                    continue;
                },
            }
        }

        if (0 < nextNx and nextNx <= name.len) {
            px = nextPx;
            nx = nextNx;
            continue;
        }
        return false;
    }
    return true;
}

test match {
    const t = @import("std").testing;

    const Case = struct {
        p: []const u8,
        n: []const u8,
        e: bool,
    };

    const cases = [_]Case{
        .{ .p = "Hello *", .n = "Hello world", .e = true },
        .{ .p = "Hello W*", .n = "Hello world", .e = false },
        .{ .p = "*ello*orl*", .n = "Hello there, world", .e = true },
        .{ .p = "*ello*orl*", .n = "Hello there, orca", .e = false },
        .{ .p = "*ello*th*or?a", .n = "Hello there, orca", .e = true },
    };

    for (cases) |case| {
        try t.expectEqual(case.e, match(case.p, case.n));
    }
}
