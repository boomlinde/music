const RNG = @This();

seed: u32 = 1,

pub fn uint(self: *RNG) u32 {
    if (self.seed == 0) self.seed = 0xffffffff;
    self.seed ^= self.seed << 13;
    self.seed ^= self.seed >> 17;
    self.seed ^= self.seed << 5;
    return self.seed;
}

pub fn float(self: *RNG) f32 {
    return @floatCast(@as(f64, @floatFromInt(self.uint())) / @as(f64, 0xffffffff));
}

pub fn floatRange(self: *RNG, lower: f32, upper: f32) f32 {
    const scale = upper - lower;
    return self.float() * scale + lower;
}

pub fn index(self: *RNG, len: usize) usize {
    return @min(len - 1, @as(usize, @intFromFloat(self.float() * @as(f32, @floatFromInt(len)))));
}

pub fn range(self: *RNG, min: usize, max: usize) usize {
    return min + self.index(max - min);
}

pub fn shuffle(self: *RNG, s: anytype) void {
    for (0..s.len) |i| {
        const r = self.range(i, s.len);
        swap(s, i, r);
    }
}

inline fn swap(s: anytype, i: usize, j: usize) void {
    const tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
}

test "call" {
    var rng = RNG{ .seed = 5 };

    _ = rng.uint();
    _ = rng.float();
}
