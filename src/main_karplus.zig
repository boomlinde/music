const std = @import("std");
const JackState = @import("JackState.zig");
const midi = @import("midi.zig");
const KarplusSynth = @import("KarplusSynth.zig");

var midiport: *JackState.Port = undefined;
var audioport: *JackState.Port = undefined;
var in = midi.In{};

var synth: KarplusSynth = .{};

pub fn main() !void {
    const name = "karplus";

    var js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerInput("midi", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);
    audioport = try js.registerOutput("out", JackState.DefaultAudioType);
    defer js.unregisterPort(audioport);

    synth.init();

    try js.activate();

    while (true) std.time.sleep(1 * std.time.ns_per_s);
}

fn cb(nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int {
    const js: *JackState = @ptrCast(@alignCast(jstate_opaque));
    var iter = JackState.iterMidi(midiport, nframes, &in) catch return 1;
    var ab = JackState.audioBuf(audioport, nframes) catch return 1;

    for (0..nframes) |f| {
        while (iter.next(@intCast(f))) |msg| synth.handleMidiEvent(msg);
        ab[f] = synth.next(@floatFromInt(js.samplerate));
    }

    return 0;
}
