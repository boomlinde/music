const std = @import("std");

current_srate: f32 = 0,
current_time: f32 = -1,
a: f32 = 0,
z: f32 = 0,

pub fn next(self: *@This(), in: f32, time: f32, srate: f32) f32 {
    if (srate != self.current_srate or time != self.current_time) {
        self.a = std.math.exp(-std.math.tau / (time * srate));
        self.current_srate = srate;
        self.current_time = time;
    }

    const b = 1 - self.a;
    self.z = (in * b) + (self.z * self.a);
    return self.z;
}

pub fn short(self: *@This(), in: f32) void {
    self.z = in;
}
