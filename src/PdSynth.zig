const midi = @import("midi.zig");
const PdVoice = @import("PdVoice.zig");
const RoundRobinManager = @import("RoundRobinManager.zig");
const Smoother = @import("Smoother.zig");

const PdSynth = @This();

const nvoices = 8;

voices: [nvoices]PdVoice = [_]PdVoice{.{}} ** nvoices,
links: [nvoices]RoundRobinManager.Link = undefined,
man: RoundRobinManager = .{},
params: PdVoice.Params = .{},
shared: PdVoice.Shared = .{},

timbre_smoother: Smoother = .{ .time = 0.01 },
mod_ratio_smoother: Smoother = .{ .time = 0.01 },
vel_ratio_smoother: Smoother = .{ .time = 0.01 },

pub fn init(self: *PdSynth) void {
    for (0..nvoices) |i| {
        self.links[i] = .{ .value = .{ .handle = i } };
        self.man.addLink(&self.links[i]);

        self.voices[i].params = &self.params;
        self.voices[i].shared = &self.shared;
    }
}

pub fn updateParams(self: *PdSynth, new_params: *const PdVoice.Params) void {
    self.params = new_params.snapshot();
}

pub fn handleMidiEvent(self: *PdSynth, event: midi.Message) void {
    switch (event) {
        inline .note_on, .note_off => |v| {
            if (v.channel != self.params.channel) return;
            if (self.man.handleEvent(event)) |ev| switch (ev) {
                .note_on => |m| self.voices[m.handle].noteOn(m.pitch, m.velocity),
                .note_off => |m| self.voices[m.handle].noteOff(),
            };
        },
        .pitch_wheel => |m| self.shared.wheel = 2 * (@as(f32, @floatFromInt(m.value)) - 8192) / 8192,
        else => {},
    }
}

pub fn next(self: *PdSynth, srate: f32) f32 {
    // Update shared smoothers
    self.shared.smooth_timbre = self.timbre_smoother.next(self.params.timbre, srate);
    self.shared.smooth_mod_ratio = self.mod_ratio_smoother.next(self.params.mod_ratio, srate);
    self.shared.smooth_vel_ratio = self.vel_ratio_smoother.next(self.params.vel_ratio, srate);

    // Calculate next sample
    var sum: f32 = 0;
    for (&self.voices) |*voice| {
        sum += voice.next(srate);
    }
    return sum;
}
