const std = @import("std");
const gui = @import("gui.zig");
const midi = @import("midi.zig");

const JackState = @import("JackState.zig");
const DigiBass = @import("DigiBass.zig");

const RGB = gui.RGB;
const Slot = gui.Slot;
const Value = gui.Value;
const Symbol = gui.Symbol;

var midiport: *JackState.Port = undefined;
var audioport: *JackState.Port = undefined;
var in = midi.In{};

var params = DigiBass.Params{};

var synth: DigiBass = .{ .channel = 0, .params = &params };

pub fn main() !void {
    const name = "digibass";
    var redraw = false;

    const bg = RGB.init(30, 30, 30);
    const fg = RGB.init(0, 100, 100);

    try gui.init();
    defer gui.deinit();

    var js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerInput("midi", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);
    audioport = try js.registerOutput("out", JackState.DefaultAudioType);
    defer js.unregisterPort(audioport);

    try js.activate();

    const layout = [2][6]Slot{
        .{
            .{ .slider = .{ .value = Value.passthrough(&params.res) } },
            .{ .slider = .{ .value = Value.passthrough(&params.timbre) } },
            .{ .slider = .{ .value = Value.passthrough(&params.feedback) } },
            .{ .slider = .{ .value = Value.passthrough(&params.decay) } },
            .{ .slider = .{ .value = Value.passthrough(&params.mod_depth) } },
            .{ .slider = .{ .value = Value.passthrough(&params.accentness) } },
        },
        .{
            .{ .slider = .{ .value = Value.intMax(u8, @ptrCast(&params.sound_type), 1) } },
            .empty,
            .empty,
            .empty,
            .empty,
            .{ .slider = .{ .value = Value.int(u4, &synth.channel) } },
        },
    };
    try gui.run(name, 800, 600, bg, fg, &redraw, layout);
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
