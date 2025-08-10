const ADREnv = @import("ADREnv.zig");
const midi = @import("midi.zig");
const std = @import("std");
const MonoLegato = @import("MonoLegato.zig");
const MonoVoiceManager = @import("MonoVoiceManager.zig");
const FMBass = @This();
const Smoother = @import("Smoother.zig");

const Accessor = @import("Accessor.zig").Accessor;

pub const Params = struct {
    car_mul: f32 = 0,
    mod_mul: f32 = 0,
    mod_depth: f32 = 0,
    channel: u4 = 0,

    pub usingnamespace Accessor(@This());
};

const param_smooth_time = 0.1;

phase: f32 = 0,
legato: MonoLegato = .{ .time = 0.06 },
man: MonoVoiceManager = .{},
params: Params = .{},
amp_env: ADREnv = .{},

car_mul_smooth: Smoother = .{},
mod_mul_smooth: Smoother = .{},
mod_depth_smooth: Smoother = .{},

pub inline fn next(self: *FMBass, srate: f32) f32 {
    const state = self.legato.next(self.man.state, srate);
    const freq = 440.0 * std.math.pow(f32, 2.0, (state.pitch - 69) / 12);
    defer self.phase = @mod(self.phase + freq / srate, 1);

    const amp_env_params: ADREnv.Params = .{
        .attack = 0.002,
        .decay = 3,
        .release = 0.03,
    };

    const car_mul = self.car_mul_smooth.next(self.params.get(.car_mul), param_smooth_time, srate);
    const mod_mul = self.mod_mul_smooth.next(self.params.get(.mod_mul), param_smooth_time, srate);
    const mod_depth = self.mod_depth_smooth.next(self.params.get(.mod_depth), param_smooth_time, srate);

    const mod = cross(self.phase, 0, mod_mul) * mod_depth * 4;
    const amp = self.amp_env.next(&amp_env_params, state.gate, srate);

    return amp * cross(self.phase, mod, car_mul);
}

pub fn handleMidiEvent(self: *FMBass, event: midi.Event) void {
    if ((event.channel() orelse return) != self.params.get(.channel)) return;
    switch (event) {
        .note_on => |e| self.man.noteOn(e.pitch, e.velocity),
        .note_off => |e| self.man.noteOff(e.pitch),
        else => {},
    }
}

fn cross(phase: f32, mod: f32, v: f32) f32 {
    const w = v * 16 + 1;
    const low = @floor(w);
    const high = low + 1;
    const mix = w - low;

    const p2p = phase * std.math.tau;

    const low_out = @sin(p2p * (low + mod));
    const high_out = @sin(p2p * (high + mod));
    const mix_out = (1 - mix) * low_out + mix * high_out;

    return mix_out;
}
