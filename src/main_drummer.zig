const std = @import("std");
const gui = @import("gui.zig");
const midi = @import("midi.zig");

const JackState = @import("JackState.zig");
const DrumSynth = @import("DrumSynth.zig");

const RGB = gui.RGB;
const Slot = gui.Slot;
const Value = gui.Value;
const Symbol = gui.Symbol;

var midiport: *JackState.Port = undefined;

var sport: *JackState.Port = undefined;
var port0: *JackState.Port = undefined;
var port1: *JackState.Port = undefined;
var port2: *JackState.Port = undefined;
var port3: *JackState.Port = undefined;

var in = midi.In{};

var params = DrumSynth.Params{};

var redraw = false;
var synth: DrumSynth = .{};

pub fn main() !void {
    const name = "drummer";

    try gui.init();
    defer gui.deinit();

    var js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerInput("midi", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);

    sport = try js.registerOutput("sum", JackState.DefaultAudioType);
    defer js.unregisterPort(sport);

    port0 = try js.registerOutput("0", JackState.DefaultAudioType);
    defer js.unregisterPort(port0);

    port1 = try js.registerOutput("1", JackState.DefaultAudioType);
    defer js.unregisterPort(port1);

    port2 = try js.registerOutput("2", JackState.DefaultAudioType);
    defer js.unregisterPort(port2);

    port3 = try js.registerOutput("3", JackState.DefaultAudioType);
    defer js.unregisterPort(port3);

    try js.activate();

    const bg = RGB.init(30, 30, 30);
    const fg = RGB.init(0, 100, 100);

    const amp_color = RGB.init(100, 150, 70);
    const mod_color = RGB.init(150, 150, 30);
    const pitch_color = RGB.init(150, 70, 70);
    const timbre_color = RGB.init(100, 150, 150);
    const bus_color = RGB.init(200, 50, 200);

    const p = Value.passthrough;
    const b = Value.int;

    const layout = [_][15]Slot{
        .{
            .{ .flag = flagIdx(0) },
            .{ .slider = .{ .value = p(&params.sets[0].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[0].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[0].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[0].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[0].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[0].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[0].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[0].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[0].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[0].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[0].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[0].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[0].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[0].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(1) },
            .{ .slider = .{ .value = p(&params.sets[1].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[1].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[1].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[1].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[1].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[1].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[1].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[1].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[1].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[1].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[1].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[1].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[1].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[1].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(2) },
            .{ .slider = .{ .value = p(&params.sets[2].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[2].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[2].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[2].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[2].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[2].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[2].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[2].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[2].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[2].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[2].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[2].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[2].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[2].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(3) },
            .{ .slider = .{ .value = p(&params.sets[3].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[3].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[3].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[3].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[3].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[3].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[3].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[3].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[3].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[3].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[3].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[3].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[3].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[3].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(4) },
            .{ .slider = .{ .value = p(&params.sets[4].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[4].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[4].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[4].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[4].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[4].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[4].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[4].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[4].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[4].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[4].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[4].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[4].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[4].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(5) },
            .{ .slider = .{ .value = p(&params.sets[5].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[5].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[5].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[5].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[5].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[5].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[5].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[5].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[5].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[5].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[5].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[5].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[5].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[5].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(6) },
            .{ .slider = .{ .value = p(&params.sets[6].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[6].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[6].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[6].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[6].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[6].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[6].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[6].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[6].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[6].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[6].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[6].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[6].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[6].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(7) },
            .{ .slider = .{ .value = p(&params.sets[7].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[7].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[7].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[7].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[7].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[7].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[7].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[7].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[7].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[7].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[7].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[7].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[7].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[7].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(8) },
            .{ .slider = .{ .value = p(&params.sets[8].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[8].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[8].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[8].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[8].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[8].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[8].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[8].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[8].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[8].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[8].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[8].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[8].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[8].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(9) },
            .{ .slider = .{ .value = p(&params.sets[9].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[9].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[9].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[9].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[9].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[9].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[9].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[9].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[9].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[9].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[9].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[9].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[9].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[9].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(10) },
            .{ .slider = .{ .value = p(&params.sets[10].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[10].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[10].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[10].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[10].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[10].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[10].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[10].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[10].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[10].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[10].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[10].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[10].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[10].bus), .color = bus_color } },
        },
        .{
            .{ .flag = flagIdx(11) },
            .{ .slider = .{ .value = p(&params.sets[11].level), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[11].amp_env.time), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[11].amp_env.shape), .color = amp_color } },
            .{ .slider = .{ .value = p(&params.sets[11].pitch), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[11].pitch_env_level), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[11].pitch_env.time), .color = pitch_color } },
            .{ .slider = .{ .value = p(&params.sets[11].timbre), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[11].timbre_env_level), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[11].timbre_env.time), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[11].timbre_env.shape), .color = timbre_color } },
            .{ .slider = .{ .value = p(&params.sets[11].mod_pitch), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[11].mod_level), .color = mod_color } },
            .{ .slider = .{ .value = p(&params.sets[11].q), .color = mod_color } },
            .{ .slider = .{ .value = b(u2, &params.sets[11].bus), .color = bus_color } },
        },
    };

    try gui.run(name, 800, 600, bg, fg, &redraw, layout);
}

fn flagIdx(comptime idx: usize) gui.Flag {
    const wrap = struct {
        fn raised(arg: *anyopaque) bool {
            _ = arg;
            return idx == @atomicLoad(usize, &synth.last_played, .seq_cst);
        }
    };

    return .{
        .arg = undefined,
        .raised = &wrap.raised,
        .color = RGB.init(255, 50, 50),
    };
}

fn cb(nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int {
    const js: *JackState = @ptrCast(@alignCast(jstate_opaque));
    var iter = JackState.iterMidi(midiport, nframes, &in) catch return 1;

    var sport_buffer = JackState.audioBuf(sport, nframes) catch return 1;
    var port0_buffer = JackState.audioBuf(port0, nframes) catch return 1;
    var port1_buffer = JackState.audioBuf(port1, nframes) catch return 1;
    var port2_buffer = JackState.audioBuf(port2, nframes) catch return 1;
    var port3_buffer = JackState.audioBuf(port3, nframes) catch return 1;

    for (0..nframes) |f| {
        while (iter.next(@intCast(f))) |msg| synth.handleMidiEvent(msg, &params, &redraw);
        const out = synth.next(&params, @floatFromInt(js.samplerate));
        sport_buffer[f] = out.sum;
        port0_buffer[f] = out.buses[0];
        port1_buffer[f] = out.buses[1];
        port2_buffer[f] = out.buses[2];
        port3_buffer[f] = out.buses[3];
    }

    return 0;
}
