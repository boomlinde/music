const std = @import("std");
const midi = @import("midi.zig");
const DrumEnv = @import("DrumEnv.zig");
const Accessor = @import("Accessor.zig").Accessor;
const Pd = @import("PdVoice.zig").Pd;
const RNG = @import("RNG.zig");
const BandpassFilter = @import("BandpassFilter.zig");

const DrumSynth = @This();

const nparamsets = 7;

voice: Voice = .{},
paramset_idx: usize = 0,

pub const Params = struct {
    sets: [nparamsets]Voice.Params = [_]Voice.Params{.{}} ** nparamsets,

    usingnamespace Accessor(@This());
};

pub inline fn next(self: *DrumSynth, params: *const Params, srate: f32) f32 {
    return self.voice.next(&params.sets[self.paramset_idx], srate);
}

pub fn handleMidiEvent(self: *DrumSynth, event: midi.Event) void {
    switch (event) {
        .note_on => |v| {
            const n = v.pitch % 12;
            self.paramset_idx = switch (n) {
                0 => 0,
                2 => 1,
                4 => 2,
                5 => 3,
                7 => 4,
                9 => 5,
                11 => 6,
                else => {
                    return;
                },
            };
            self.voice.trigger();
        },
        else => {},
    }
}

const Voice = struct {
    amp_env: DrumEnv = .{},
    pitch_env: DrumEnv = .{},
    timbre_env: DrumEnv = .{},
    phase: f32 = 0,
    noise: RNG = .{},
    mod: BandpassFilter = .{},

    const Params = struct {
        amp_env: DrumEnv.Params = .{},
        pitch_env: DrumEnv.Params = .{},
        timbre_env: DrumEnv.Params = .{},
        mod_env: DrumEnv.Params = .{},
        pitch_env_level: f32 = 0,
        timbre_env_level: f32 = 0,
        pitch: f32 = 0.1,
        timbre: f32 = 0,
        mod_level: f32 = 0,
        mod_pitch: f32 = 0.3,
        q: f32 = 0,

        usingnamespace Accessor(@This());
    };

    fn trigger(self: *Voice) void {
        self.amp_env.trigger();
        self.pitch_env.trigger();
        self.timbre_env.trigger();
        self.mod.reset();
        self.phase = 0;
    }

    pub inline fn next(self: *Voice, params: *const Voice.Params, srate: f32) f32 {
        const noise = self.noise.float();
        const ae = self.amp_env.next(&params.amp_env, srate);
        const pe = self.pitch_env.next(&params.pitch_env, srate);
        const te = self.timbre_env.next(&params.timbre_env, srate);
        const ml = params.get(.mod_level) * 2;

        const tl = params.get(.timbre_env_level);
        const timbre = params.get(.timbre) * ((1 - tl) + tl * te);

        const mpitch: f32 = 25 + 50 * params.get(.pitch) + 50 * pe * params.get(.pitch_env_level);
        const freq = 440.0 * std.math.pow(f32, 2.0, (mpitch - 69) / 12.0);

        const mod_pitch: f32 = 25 + 100 * params.get(.mod_pitch);
        const mod_freq = 440.0 * std.math.pow(f32, 2.0, (mod_pitch - 69) / 12.0);
        const pq = params.get(.q);
        const mod_q = (pq * pq) * 19 + 1;

        const mod = self.mod.next(noise, mod_freq, mod_q, srate);

        defer self.phase = @mod(self.phase + freq / srate, 1);

        const pd = Pd{ .x = (1 - logize3(timbre)), .y = 1, .p = 1, .n = 1 };

        return pd.wave(self.phase + ml * ml * mod) * ae;
    }
};

inline fn logize3(a: f32) f32 {
    const m = 1 - a;
    return 1 - m * m * m;
}
