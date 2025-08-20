const std = @import("std");
const Adsr = @import("Adsr.zig");

const PdVoice = @This();

pub const Params = struct {
    timbre: f32 = 0,
    class: u3 = 0,
    amp_env: Adsr.Params = .{},
    mod_env: Adsr.Params = .{},
    mod_ratio: f32 = 0.5,
    vel_ratio: f32 = 0.5,
    channel: u4 = 0,
    reset_phase: bool = true,

    pub usingnamespace @import("snapshotter.zig").Snapshotter(@This());
};

pub const Shared = struct {
    smooth_timbre: f32 = 0,
    smooth_mod_ratio: f32 = 0,
    smooth_vel_ratio: f32 = 0,
    wheel: f32 = 0,
};

phase: f32 = 0,
pitch: f32 = 0,
velocity: f32 = 0,
amp_env: Adsr = Adsr.init(0.3),
mod_env: Adsr = Adsr.init(0.1),
gate: bool = false,
params: *Params = undefined,
shared: *Shared = undefined,

inline fn logize3(a: f32) f32 {
    const m = 1 - a;
    return 1 - m * m * m;
}

inline fn logize2(a: f32) f32 {
    const m = 1 - a;
    return 1 - m * m;
}

pub inline fn next(self: *PdVoice, srate: f32) f32 {
    const freq = 440.0 * std.math.pow(f32, 2.0, (self.pitch + self.shared.wheel - 69) / 12.0);
    defer self.phase = @mod(self.phase + freq / srate, 1);

    const mod_ratio = self.shared.smooth_mod_ratio;
    const vel_ratio = self.shared.smooth_vel_ratio;

    const mod = (1 - mod_ratio) + self.mod_env.next(&self.params.mod_env, self.gate, srate) * mod_ratio;
    const vel = (1 - vel_ratio) + self.velocity * self.velocity * vel_ratio;
    const timbre = self.shared.smooth_timbre * mod * vel;

    var pd: Pd = undefined;
    switch (self.params.class) {
        0 => pd = .{ .x = (1 - logize3(timbre)), .y = 1, .p = 1, .n = 1 }, // Square
        1 => pd = .{ .x = 0.5 - (0.5 * logize3(timbre)), .y = 0.5, .p = 1, .n = 0 }, // Saw
        2 => pd = .{ .x = 0.95 * logize2(timbre), .y = 0, .p = 0, .n = 0 }, // Pulse
        3 => pd = .{ .x = 0.95 * logize2(timbre), .y = 0, .p = 0, .n = 0, .q = 2 }, // Pulse2
        4 => pd = .{ .x = 0.9 - logize3(timbre) * 0.9, .y = 0.9, .p = 1, .n = 5 }, // Fat
        5 => pd = .{ .x = 0.5 - (0.48 * logize3(timbre)), .y = 0.5, .p = 0, .n = 2 }, // Buzz
        6 => pd = .{ .x = (1 - logize3(timbre)), .y = 1, .p = 0.25, .n = 1 }, // Res
        7 => pd = .{ .x = 0.25 + 0.7 * logize2(timbre), .y = 0.25, .p = 0, .n = 0, .q = 2 }, // ResSaw
    }

    return pd.wave(self.phase) * 0.5 * self.amp_env.next(&self.params.amp_env, self.gate, srate) * self.velocity * self.velocity;
}

pub fn noteOn(self: *PdVoice, pitch: u7, velocity: u7) void {
    self.pitch = @floatFromInt(pitch);
    self.velocity = @as(f32, @floatFromInt(velocity)) / 127;
    self.gate = true;
    if (self.params.reset_phase) self.phase = 0;
}

pub fn noteOff(self: *PdVoice) void {
    self.gate = false;
}

pub const Pd = struct {
    x: f32 = 0.5,
    y: f32 = 0.5,
    n: f32 = 0,
    p: f32 = 0,
    q: f32 = 1,

    pub fn wave(self: Pd, ph: f32) f32 {
        const ph_mod = @mod(ph, 1);
        return @sin((self.p * 0.25 + self.phase(ph_mod)) * std.math.tau * self.q);
    }

    inline fn phase(self: Pd, ph: f32) f32 {
        const n = self.n + 1;
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
