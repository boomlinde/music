const std = @import("std");
const midi = @import("midi.zig");
const DrumEnv = @import("DrumEnv.zig");
const Accessor = @import("Accessor.zig").Accessor;
const Pd = @import("PdVoice.zig").Pd;
const RNG = @import("RNG.zig");
const BandpassFilter = @import("BandpassFilter.zig");

const DrumSynth = @This();

voices: [4]Voice = [_]Voice{.{}} ** 4,
indices: [4]usize = [_]usize{0} ** 4,
last_played: usize = 9999,

pub const Params = struct {
    sets: [12]Voice.Params = [_]Voice.Params{.{}} ** 12,

    usingnamespace Accessor(@This());
};

pub inline fn next(self: *DrumSynth, params: *const Params, srate: f32) f32 {
    var out: f32 = 0;
    for (&self.voices, 0..) |*voice, i| {
        out += voice.next(&params.sets[self.indices[i]], srate);
    }
    return @min(1, @max(-1, out));
}

pub fn handleMidiEvent(self: *DrumSynth, event: midi.Event, params: *const Params, redraw: *bool) void {
    switch (event) {
        .note_on => |v| {
            const idx = v.pitch % 12;
            const set = &params.sets[idx];
            const bus = set.get(.bus);
            self.indices[bus] = idx;
            self.voices[bus].trigger();
            @atomicStore(usize, &self.last_played, idx, .seq_cst);
            @atomicStore(bool, redraw, true, .seq_cst);
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
        level: f32 = 1,
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
        bus: u2 = 0,

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
        if (self.amp_env.state == 0) return 0;
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

        const level = params.get(.level);

        return pd.wave(self.phase + ml * ml * mod) * ae * level * level;
    }
};

inline fn logize3(a: f32) f32 {
    const m = 1 - a;
    return 1 - m * m * m;
}
