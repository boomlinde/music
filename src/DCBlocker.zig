const std = @import("std");

const freq: f32 = 10;

in: f32 = 0,
out: f32 = 0,

pub fn next(self: *@This(), in: f32, srate: f32) f32 {
    const coef = 1 - std.math.tau * freq / srate;

    self.out = in - self.in + coef * self.out;
    self.in = in;
    return self.out;
}
