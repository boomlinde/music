const std = @import("std");
const midi = @import("midi.zig");
const JackState = @import("JackState.zig");
const RGB = @import("gui.zig").RGB;
const Vec2 = @import("gui.zig").Vec2;

var midiport: *JackState.Port = undefined;
var in = midi.In{};

var notes: [16][128]bool = [1][128]bool{[1]bool{false} ** 128} ** 16;
var js: JackState = undefined;

const c = @cImport({
    @cInclude("SDL.h");
});

pub fn main() anyerror!void {
    js = try JackState.init("midivis", &process, null);
    defer js.deinit();

    midiport = try js.registerInput("in", JackState.DefaultMidiType);
    defer js.unregisterPort(midiport);

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS) != 0)
        return error.FailedInitSDL;
    defer c.SDL_Quit();

    const w = c.SDL_CreateWindow(
        "midivis",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        1024,
        768,
        c.SDL_WINDOW_RESIZABLE,
    ) orelse return error.FailedCreatingWindow;
    defer c.SDL_DestroyWindow(w);

    const r = c.SDL_CreateRenderer(
        w,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse
        return error.FailedCreatingRenderer;
    errdefer c.SDL_DestroyRenderer(r);

    try js.activate();

    mainloop: while (true) {
        var c_w_width: c_int = 0;
        var c_w_height: c_int = 0;
        c.SDL_GetWindowSize(w, &c_w_width, &c_w_height);
        const w_dim = Vec2{
            .x = @floatFromInt(c_w_width),
            .y = @floatFromInt(c_w_height),
        };

        RGB.init(128, 64, 32).fill(r);
        for (0..16) |ch| {
            const fch: f32 = @floatFromInt(ch);
            var f: f32 = 0;
            for (0..128) |i| {
                if (note_is_black[i % 12]) continue;
                defer f += 1;

                const key_width = w_dim.x / nwhites;
                const key_height = w_dim.y / 16;
                const x1 = @as(f32, f) * key_width;
                const x2 = @as(f32, f + 1) * key_width;
                const y1: f32 = fch * key_height;
                const y2 = (fch + 1) * key_height;

                const rect = c.SDL_Rect{
                    .x = @intFromFloat(@round(x1)),
                    .y = @intFromFloat(@round(y1)),
                    .w = @intFromFloat(@round(x2 - x1)),
                    .h = @intFromFloat(@round(y2 - y1)),
                };

                const gate = @atomicLoad(bool, &notes[ch][i], .seq_cst);
                if (gate)
                    RGB.init(255, 0, 0).apply(r)
                else
                    RGB.init(255, 255, 255).apply(r);
                _ = c.SDL_RenderFillRect(r, &rect);

                RGB.init(0, 0, 0).apply(r);
                _ = c.SDL_RenderDrawRect(r, &rect);
            }

            f = 0;
            for (0..128) |i| {
                if (!note_is_black[i % 12]) {
                    f += 1;
                    continue;
                }

                const wkey_height = w_dim.y / 16;
                const key_height = 0.6 * wkey_height;
                const wkey_width = w_dim.x / nwhites;
                const key_width = 0.8 * wkey_width;
                const x1 = @as(f32, f) * wkey_width - key_width / 2;
                const x2 = @as(f32, f) * wkey_width + key_width / 2;
                const y1: f32 = fch * wkey_height;
                const y2 = fch * wkey_height + key_height;

                const rect = c.SDL_Rect{
                    .x = @intFromFloat(@round(x1)),
                    .y = @intFromFloat(@round(y1)),
                    .w = @intFromFloat(@round(x2 - x1)),
                    .h = @intFromFloat(@round(y2 - y1)),
                };

                const gate = @atomicLoad(bool, &notes[ch][i], .seq_cst);
                if (gate)
                    RGB.init(255, 0, 0).apply(r)
                else
                    RGB.init(0, 0, 0).apply(r);
                _ = c.SDL_RenderFillRect(r, &rect);

                RGB.init(0, 0, 0).apply(r);
                _ = c.SDL_RenderDrawRect(r, &rect);
            }
        }
        _ = c.SDL_RenderPresent(r);

        var ev: c.SDL_Event = undefined;
        while (0 != c.SDL_PollEvent(&ev)) switch (ev.type) {
            c.SDL_QUIT => break :mainloop,
            else => {},
        };
    }
}

fn process(nframes: JackState.NFrames, _: ?*anyopaque) callconv(.C) c_int {
    var iter = JackState.iterMidi(midiport, nframes, &in) catch return 1;

    for (0..nframes) |f| {
        while (iter.next(@intCast(f))) |msg| switch (msg) {
            .note_on => |v| {
                const addr = &notes[v.channel][v.pitch];
                @atomicStore(bool, addr, v.velocity != 0, .seq_cst);
            },
            .note_off => |v| {
                const addr = &notes[v.channel][v.pitch];
                @atomicStore(bool, addr, false, .seq_cst);
            },
            .control_change => |v| switch (v.controller) {
                0x7b => for (0..128) |i| { // All notes off
                    std.log.err("ajabaja", .{});
                    const addr = &notes[v.channel][i];
                    @atomicStore(bool, addr, false, .seq_cst);
                },
                else => {},
            },
            else => {},
        };
    }

    return 0;
}

const note_is_black = [12]bool{
    false,
    true,
    false,
    true,
    false,
    false,
    true,
    false,
    true,
    false,
    true,
    false,
};

const nwhites = wh: {
    var count = 0;
    for (0..128) |i| {
        if (!note_is_black[i % 12]) count += 1;
    }
    break :wh count;
};
