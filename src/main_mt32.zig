const std = @import("std");
const midi = @import("midi.zig");
const gui = @import("gui.zig");

const JackState = @import("JackState.zig");
const RGB = gui.RGB;
const Slot = gui.Slot;
const Value = gui.Value;

pub const c = @cImport({
    @cDefine("MT32EMU_API_TYPE", "1");
    @cInclude("mt32emu.h");
});

var in = midi.In{};

var midiport: *JackState.Port = undefined;
var left: *JackState.Port = undefined;
var right: *JackState.Port = undefined;

var munt_ctx: c.mt32emu_context = undefined;

var redraw = false;

var guipatches: [8]u7 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
var cbpatches: [8]u7 = [_]u7{127} ** 8;

var guirange: [8]u5 = [_]u5{2} ** 8;
var cbrange: [8]u5 = [_]u5{12} ** 8;

pub fn main() !void {
    const name = "jack-mt32";

    try gui.init();
    defer gui.deinit();

    var js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerInput("midi", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);

    left = try js.registerOutput("left", JackState.DefaultAudioType);
    defer js.unregisterPort(left);

    right = try js.registerOutput("right", JackState.DefaultAudioType);
    defer js.unregisterPort(right);

    munt_ctx = c.mt32emu_create_context(.{ .v1 = null }, null) orelse return error.InitMuntCtx;
    defer c.mt32emu_free_context(munt_ctx);

    {
        const ctrl_res = c.mt32emu_add_rom_file(munt_ctx, "ctrl_mt32.rom");
        if (ctrl_res != c.MT32EMU_RC_ADDED_CONTROL_ROM) return error.LoadRoms;
        const pcm_res = c.mt32emu_add_rom_file(munt_ctx, "pcm_mt32.rom");
        if (pcm_res != c.MT32EMU_RC_ADDED_PCM_ROM) return error.LoadRoms;
    }

    c.mt32emu_set_stereo_output_samplerate(munt_ctx, @floatFromInt(js.samplerate));
    c.mt32emu_set_samplerate_conversion_quality(munt_ctx, 3);
    c.mt32emu_select_renderer_type(munt_ctx, 1);

    if (c.MT32EMU_RC_OK != c.mt32emu_open_synth(munt_ctx)) return error.OpenSynth;
    defer c.mt32emu_close_synth(munt_ctx);

    c.mt32emu_configure_midi_event_queue_sysex_storage(munt_ctx, 32768);

    try js.activate();

    const bg = RGB.init(30, 30, 30);
    const fg = RGB.init(0, 100, 100);

    const layout = [_][8]Slot{
        .{
            .{ .slider = .{ .value = Value.int(u7, &guipatches[0]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[1]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[2]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[3]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[4]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[5]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[6]) } },
            .{ .slider = .{ .value = Value.int(u7, &guipatches[7]) } },
        },
        .{
            .{ .slider = .{ .value = Value.int(u5, &guirange[0]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[1]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[2]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[3]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[4]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[5]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[6]) } },
            .{ .slider = .{ .value = Value.int(u5, &guirange[7]) } },
        },
    };

    try gui.run(name, 400, 200, bg, fg, &redraw, layout);
}

fn cb(nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int {
    _ = jstate_opaque;
    var iter = JackState.iterMidi(midiport, nframes, &in) catch return 1;

    var left_buffer = JackState.audioBuf(left, nframes) catch return 1;
    var right_buffer = JackState.audioBuf(right, nframes) catch return 1;

    var changed = false;
    for (&guipatches, &cbpatches, 0..) |*guip, *cbp, i| {
        const guiv = @atomicLoad(u7, guip, .seq_cst);

        if (cbp.* != guiv) {
            cbp.* = guiv;
            const status: u8 = @as(u8, @intCast(i)) + 1 | 0xc0;
            const data = [2]u8{ status, guiv };
            c.mt32emu_parse_stream(munt_ctx, &data, 2);
            cbrange[i] = cbrange[i] ^ 0x1f;
            changed = true;
        }
    }

    for (&guirange, &cbrange, 0..) |*guip, *cbp, i| {
        const guiv = @atomicLoad(u5, guip, .seq_cst);

        if (cbp.* != guiv) {
            cbp.* = guiv;
            const status: u8 = @as(u8, @intCast(i)) + 1 | 0xb0;

            const data = [_]u8{
                status,
                100,
                0,
                status,
                101,
                0,
                status,
                6,
                @min(24, guiv),
            };
            c.mt32emu_parse_stream(munt_ctx, &data, data.len);
            changed = true;
        }
    }
    if (changed) c.mt32emu_flush_midi_queue(munt_ctx);

    var current_time: usize = 0;
    while (iter.get()) |ev| {
        c.mt32emu_parse_stream(munt_ctx, @ptrCast(ev.buffer), @intCast(ev.size));
        if (ev.time == current_time) continue;
        c.mt32emu_render_float(munt_ctx, &buffer[current_time * 2], @intCast(ev.time - current_time));
        current_time = @intCast(ev.time);
    }
    if (current_time != nframes) {
        c.mt32emu_render_float(munt_ctx, &buffer[current_time * 2], @intCast(nframes - current_time));
    }

    for (0..nframes) |i| {
        left_buffer[i] = buffer[i * 2];
        right_buffer[i] = buffer[i * 2 + 1];
    }
    return 0;
}

var buffer: [65536]f32 = undefined;
