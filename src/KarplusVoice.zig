const KarplusVoice = @This();

const std = @import("std");
const KarplusStrongResonator = @import("KarplusStrongResonator.zig");
const DrumEnv = @import("DrumEnv.zig");
const RNG = @import("RNG.zig");

pub const Shared = struct {
    wheel: f32 = 0,
};

resonator: KarplusStrongResonator,
exciter: Exciter = .{},
pitch: f32 = 0,
velocity: f32 = 0,
shared: *Shared = undefined,

pub inline fn next(self: *KarplusVoice, srate: f32) f32 {
    const excitation = self.exciter.next(srate) * self.velocity * self.velocity;
    const freq = 440.0 * std.math.pow(f32, 2.0, (self.pitch + self.shared.wheel - 69) / 12.0);
    return self.resonator.next(excitation, freq, srate);
}

pub fn noteOn(self: *KarplusVoice, pitch: u7, velocity: u7) void {
    self.pitch = @floatFromInt(pitch);

    self.velocity = @as(f32, @floatFromInt(velocity)) / 127;
    self.exciter.trigger();
}

const Exciter = struct {
    rng: RNG = .{},
    env: DrumEnv = .{},

    inline fn next(self: *Exciter, srate: f32) f32 {
        return (2 * self.rng.float() - 1) * self.env.next(&.{ .time = 0.05 }, srate);
    }

    inline fn trigger(self: *Exciter) void {
        self.env.trigger();
    }
};
