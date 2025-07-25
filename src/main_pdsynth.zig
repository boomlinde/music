const std = @import("std");
const gui = @import("gui.zig");
const midi = @import("midi.zig");

const JackState = @import("JackState.zig");
const PdVoice = @import("PdVoice.zig");
const PdSynth = @import("PdSynth.zig");

const RGB = gui.RGB;
const Slot = gui.Slot;
const Value = gui.Value;
const Symbol = gui.Symbol;

var midiport: *JackState.Port = undefined;
var audioport: *JackState.Port = undefined;
var in = midi.In{};

var params = PdVoice.Params{};

var synth: PdSynth = .{};
var redraw = false;

pub fn main() !void {
    const name = "pdsynth";

    try gui.init();
    defer gui.deinit();

    synth.init();

    var js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerInput("midi", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);
    audioport = try js.registerOutput("out", JackState.DefaultAudioType);
    defer js.unregisterPort(audioport);

    try js.activate();

    const bg = RGB.init(30, 30, 30);
    const fg = RGB.init(0, 100, 100);

    const layout = [4][4]Slot{
        .{
            .{ .slider = .{ .value = Value.passthrough(&params.timbre), .symbol = Symbol.sine_wave } },
            .{ .slider = .{ .value = Value.int(@TypeOf(params.class), &params.class), .symbol = Symbol.hexagon } },
            .{ .slider = .{ .value = Value.passthrough(&params.mod_ratio), .symbol = Symbol.triangle } },
            .{ .slider = .{ .value = Value.passthrough(&params.vel_ratio), .symbol = Symbol.square } },
        },
        .{
            .{ .slider = .{ .value = Value.passthrough(&params.mod_env.a), .color = RGB.init(210, 210, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.mod_env.d), .color = RGB.init(210, 210, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.mod_env.s), .color = RGB.init(210, 210, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.mod_env.r), .color = RGB.init(210, 210, 100) } },
        },
        .{
            .{ .slider = .{ .value = Value.passthrough(&params.amp_env.a), .color = RGB.init(210, 100, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.amp_env.d), .color = RGB.init(210, 100, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.amp_env.s), .color = RGB.init(210, 100, 100) } },
            .{ .slider = .{ .value = Value.passthrough(&params.amp_env.r), .color = RGB.init(210, 100, 100) } },
        },
        .{
            .{ .slider = .{ .value = Value.int(@TypeOf(params.channel), &params.channel), .color = RGB.init(180, 100, 180) } },
            .{ .slider = .{ .value = Value.boolean(&params.reset_phase), .color = RGB.init(180, 100, 180) } },
            .empty,
            .empty,
        },
    };

    try gui.run(name, 800, 600, bg, fg, &redraw, layout);
}

fn cb(nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int {
    const js: *JackState = @ptrCast(@alignCast(jstate_opaque));
    var iter = JackState.iterMidi(midiport, nframes, &in) catch return 1;
    var ab = JackState.audioBuf(audioport, nframes) catch return 1;

    synth.updateParams(&params);
    for (0..nframes) |f| {
        while (iter.next(@intCast(f))) |msg| synth.handleMidiEvent(msg);
        ab[f] = synth.next(@floatFromInt(js.samplerate));
    }

    return 0;
}
