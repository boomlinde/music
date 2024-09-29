const std = @import("std");
const Adsr = @import("Adsr.zig");
const Smoother = @import("Smoother.zig");

const PdVoice = @This();

pub const Params = struct {
    timbre: f32 = 0,
    class: u2 = 0,
    amp_env: Adsr.Params = .{},
    mod_env: Adsr.Params = .{},
    mod_ratio: f32 = 0.5,
    vel_ratio: f32 = 0.5,

    pub usingnamespace @import("snapshotter.zig").Snapshotter(@This());
};

timbre_smoother: Smoother = .{ .time = 0.01 },
mod_ratio_smoother: Smoother = .{ .time = 0.01 },
vel_ratio_smoother: Smoother = .{ .time = 0.01 },
phase: f32 = 0,
pitch: f32 = 0,
wheel: f32 = 0,
velocity: f32 = 0,
amp_env: Adsr = Adsr.init(),
mod_env: Adsr = Adsr.init(),
gate: bool = false,

inline fn logize(a: f32) f32 {
    return 1 - (1 - a) * (1 - a);
}

pub inline fn next(self: *PdVoice, params: *const Params, srate: f32) f32 {
    const freq = 440.0 * std.math.pow(f32, 2.0, (self.pitch + self.wheel - 69) / 12.0);
    defer self.phase = @mod(self.phase + freq / srate, 1);

    const mod_ratio = self.mod_ratio_smoother.next(params.mod_ratio, srate);
    const vel_ratio = self.vel_ratio_smoother.next(params.vel_ratio, srate);

    const mod = (1 - mod_ratio) + self.mod_env.next(&params.mod_env, self.gate, srate) * mod_ratio;
    const vel = (1 - vel_ratio) + self.velocity * self.velocity * vel_ratio;
    const timbre = self.timbre_smoother.next(params.timbre, srate) * mod * vel;

    var pd: Pd = undefined;
    switch (params.class) {
        0 => pd = .{ .x = (1 - logize(timbre)), .y = 1, .p = 1, .n = 1 }, // Square
        1 => pd = .{ .x = 0.5 - (0.5 * logize(timbre)), .y = 0.5, .p = 1, .n = 0 }, // Saw
        2 => pd = .{ .x = 0.95 * logize(timbre), .y = 0, .p = 0, .n = 0 }, // Pulse
        3 => pd = .{ .x = 0.9 - logize(timbre) * 0.9, .y = 0.9, .p = 1, .n = 3 }, // Fat
    }

    return pd.wave(self.phase) * 0.5 * self.amp_env.next(&params.amp_env, self.gate, srate) * self.velocity * self.velocity;
}

pub fn noteOn(self: *PdVoice, pitch: u7, velocity: u7) void {
    self.pitch = @floatFromInt(pitch);
    self.velocity = @as(f32, @floatFromInt(velocity)) / 127;
    self.gate = true;
    self.phase = 0;
}

pub fn noteOff(self: *PdVoice, velocity: u7) void {
    _ = velocity;
    self.gate = false;
}

pub fn pitchWheel(self: *PdVoice, value: u14) void {
    self.wheel = 2 * (@as(f32, @floatFromInt(value)) - 8192) / 8192;
}

pub const Pd = struct {
    x: f32 = 0.5,
    y: f32 = 0.5,
    n: u2 = 0,
    p: f32 = 0,

    fn wave(self: Pd, ph: f32) f32 {
        return @sin((self.p * 0.25 + self.phase(ph)) * std.math.tau);
    }

    inline fn phase(self: Pd, ph: f32) f32 {
        const n = @as(f32, @floatFromInt(self.n)) + 1;
        return @mod(self.singlePhase(ph * n) / n, n);
    }

    inline fn singlePhase(self: Pd, ph: f32) f32 {
        const mp = @mod(ph, 1);
        return @floor(ph) + if (mp < self.x)
            mp * (self.y / self.x)
        else
            (mp - self.x) * ((1 - self.y) / (1 - self.x)) + self.y;
    }
};
