const std = @import("std");
const KarplusSynth = @This();

const KarplusVoice = @import("KarplusVoice.zig");
const midi = @import("midi.zig");
const RoundRobinManager = @import("RoundRobinManager.zig");

const nvoices = 16;
const maxdelay = 48000;

man: RoundRobinManager = .{},
voices: [nvoices]KarplusVoice = undefined,
buffer: [nvoices][maxdelay]f32 = undefined,
shared: KarplusVoice.Shared = .{},
links: [nvoices]RoundRobinManager.Link = undefined,

pub fn init(self: *KarplusSynth) void {
    for (0..nvoices) |v_idx| {
        self.links[v_idx] = .{ .value = .{ .handle = v_idx } };
        self.man.addLink(&self.links[v_idx]);

        for (0..maxdelay) |i| self.buffer[v_idx][i] = 0;
        self.voices[v_idx] = .{ .resonator = .{ .delayline = .{ .delay = .{
            .buffer = &self.buffer[v_idx],
        } } }, .shared = &self.shared };
    }
}

pub fn handleMidiEvent(self: *KarplusSynth, event: midi.Event) void {
    switch (event) {
        inline .note_on, .note_off => if (self.man.handleEvent(event)) |ev| switch (ev) {
            .note_on => |m| self.voices[m.handle].noteOn(m.pitch, m.velocity),
            else => {},
        },
        .pitch_wheel => |m| {
            self.shared.wheel = 2 * (@as(f32, @floatFromInt(m.value)) - 8192) / 8192;
        },
        else => {},
    }
}

pub inline fn next(self: *KarplusSynth, srate: f32) f32 {
    var sum: f32 = 0;
    for (&self.voices) |*voice| {
        sum += voice.next(srate);
    }
    return sum;
}
