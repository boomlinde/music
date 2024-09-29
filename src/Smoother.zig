const std = @import("std");

current_srate: f32 = 0,
a: f32 = 0,
z: f32 = 0,
time: f32,

pub fn next(self: *@This(), in: f32, srate: f32) f32 {
    if (srate != self.current_srate) {
        self.a = std.math.exp(-std.math.tau / (self.time * srate));
        self.current_srate = srate;
    }

    const b = 1 - self.a;
    self.z = (in * b) + (self.z * self.a);
    return self.z;
}
