const ADREnv = @import("ADREnv.zig");
const midi = @import("midi.zig");
const std = @import("std");
const MonoLegato = @import("MonoLegato.zig");
const MonoVoiceManager = @import("MonoVoiceManager.zig");
const PDBass = @This();
const Smoother = @import("Smoother.zig");
const ADEnv = @import("ADEnv.zig");

const Accessor = @import("Accessor.zig").Accessor;

pub const Params = struct {
    timbre: f32 = 0.5 - 0.125,
    mod_depth: f32 = 0.5,

    res: f32 = 1,
    feedback: f32 = 0,

    decay: f32 = 0.2,
    accentness: f32 = 0.3,

    pub usingnamespace Accessor(@This());
};

const param_smooth_time = 0.1;
const bend_smooth_time = 0.01;

channel: u4,
params: *const Params,

bend: f32 = 0,
phase: f32 = 0,
prev_phase: f32 = 0,
res_phase: f32 = 0,
res2_phase: f32 = 0,
legato: MonoLegato = .{ .time = 0.06 },
man: MonoVoiceManager = .{},
amp_env: ADREnv = .{},
prev: f32 = 0,
prev_res: f32 = 0,
mod_env: ADEnv = .{},
prev_gate: bool = false,

bend_smooth: Smoother = .{},

accentness_smooth: Smoother = .{},
res_smooth: Smoother = .{},
timbre_smooth: Smoother = .{},
feedback_smooth: Smoother = .{},
mod_smooth: Smoother = .{},

pub fn short(self: *PDBass) void {
    self.accentness_smooth.short(self.params.get(.accentness));
    self.timbre_smooth.short(self.params.get(.timbre));
    self.res_smooth.short(self.params.get(.res));
    self.mod_smooth.short(self.params.get(.mod_depth));
    self.feedback_smooth.short(self.params.get(.feedback));
}

pub inline fn next(self: *PDBass, srate: f32) f32 {
    const accentness_raw = self.accentness_smooth.next(self.params.get(.accentness), param_smooth_time, srate);
    const bend = self.bend_smooth.next(self.bend, bend_smooth_time, srate);
    const timbre = self.timbre_smooth.next(self.params.get(.timbre), param_smooth_time, srate);
    const res = self.res_smooth.next(self.params.get(.res), param_smooth_time, srate);
    const mod = self.mod_smooth.next(self.params.get(.mod_depth), param_smooth_time, srate);
    const feedback = self.feedback_smooth.next(self.params.get(.feedback), param_smooth_time, srate);
    const state = self.legato.next(self.man.state, srate);

    const res2_amp = r2a: {
        const flat_timbre = @max(0, timbre * 2 - 1);
        const ix = (1 - flat_timbre * 16);
        break :r2a @min(1, 1 - ix * ix * ix);
    };

    if (self.man.state.gate and !self.prev_gate) {
        self.mod_env.trigger();
    }
    self.prev_gate = self.man.state.gate;

    const accentness = if (state.velocity >= 96) accentness_raw else 0;
    const mp: ADEnv.Params = if (accentness > 0)
        .{
            .attack = 0.05,
            .decay = 0.2,
            .attack_shape = 1,
            .decay_shape = 0.5,
        }
    else
        .{
            .attack = 0,
            .decay = self.params.get(.decay),
            .attack_shape = 0.5,
            .decay_shape = 0.5,
        };
    const mod_env = self.mod_env.next(&mp, srate);

    const fb = self.prev * feedback;

    const pitch = state.pitch + bend;

    const amod = lerp(mod, 1, accentness);
    const nt = normal(timbre);
    const nt4 = 1 - (1 - nt) * (1 - nt) * (1 - nt);
    const total_mod = lerp(nt, 1, lerp(0, accentness, nt4)) * lerp(1, mod_env, amod);

    const res_freq = 440.0 * std.math.pow(f32, 2.0, (total_mod * 96 + 32 - 69) / 12);
    defer self.res_phase = @mod(self.res_phase + res_freq / srate, 1);
    defer self.res2_phase = @mod(self.res2_phase + res_freq / srate, 1);

    const freq = 440.0 * std.math.pow(f32, 2.0, (pitch - 69) / 12);
    defer {
        const new_phase = @mod(self.phase + freq / srate, 1);

        if (new_phase < self.phase) self.res_phase = 0;
        if (@mod(new_phase * 2, 1) < @mod(self.phase * 2, 1)) self.res2_phase = 0;

        self.phase = new_phase;
    }

    const amp_env_params: ADREnv.Params = .{
        .attack = 0.0001,
        .decay = 3,
        .release = 0.03,
    };

    const amp = self.amp_env.next(&amp_env_params, state.gate, srate);

    const falloff = falloffFunc(self.phase, res);
    const falloff2 = falloffFunc(@mod(self.phase + 0.5, 1), res);
    const nt_notrack = total_mod * (1 - clamp01((pitch - 24) / 96));
    const t: OscType = if (timbre > 0.5) .sqr else .saw;
    self.prev_res = 2 * res * falloff * falloff * falloff * @sin(self.res_phase * std.math.tau);
    self.prev_res += res2_amp * (-2 * res * falloff2 * falloff2 * falloff2 * @sin(self.res2_phase * std.math.tau));
    self.prev = clamp((pdparams(clamp01(nt_notrack), t).wave(self.phase + fb) * 1 + self.prev_res)) * amp;
    return self.prev;
}

pub inline fn falloffFunc(phase: f32, factor: f32) f32 {
    return @max(0, 1 - phase / @max(0.01, factor));
    // return 1 - phase;
}

pub fn handleMidiEvent(self: *PDBass, event: midi.Event) void {
    if ((event.channel() orelse return) != self.channel) return;
    switch (event) {
        .note_on => |e| self.man.noteOn(e.pitch, e.velocity),
        .note_off => |e| self.man.noteOff(e.pitch),
        .pitch_wheel => |m| self.bend = 2 * (@as(f32, @floatFromInt(m.value)) - 8192) / 8192,
        else => {},
    }
}

pub fn mod_env_params(accentness: f32, user_params: ADEnv.Params) ADEnv.Params {
    return .{ .time = lerp(user_params.time, 0.2, accentness), .shape = user_params.shape };
}

fn lerp(a: f32, b: f32, m: f32) f32 {
    return (1 - m) * a + m * b;
}

inline fn clamp01(a: f32) f32 {
    return @max(0, @min(1, a));
}

inline fn clamp(a: f32) f32 {
    return @max(-1, @min(1, a));
}

inline fn dual(control: f32) struct { a: f32, b: f32 } {
    return if (control >= 0.5)
        .{ .a = normal(control), .b = 0 }
    else
        .{ .b = normal(control), .a = 0 };
}

fn normal(control: f32) f32 {
    return if (control >= 0.5)
        (control - 0.5) * 2
    else
        1 - control * 2;
}

const OscType = enum { sqr, saw };

fn pdparams(control: f32, t: OscType) Pd {
    return switch (t) {
        .sqr => .{ .x = (1 - logize3(control)), .y = 1, .p = 1, .n = 1 }, // Square
        .saw => .{ .x = 0.5 - (0.5 * logize3(control)), .y = 0.5, .p = 1, .n = 0 }, // Saw
    };
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

inline fn logize3(a: f32) f32 {
    const m = 1 - a;
    return 1 - m * m * m;
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
