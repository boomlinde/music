const std = @import("std");

const mulmax = 8;

fn getscale(phase: f32, mod: f32, v: f32) f32 {
    const w = v * 8 + 1;
    const low = @floor(w);
    const high = low + 1;
    const mix = w - low;

    const p2p = phase * std.math.tau;

    const low_out = @sin(p2p * low + mod);
    const high_out = @sin(p2p * high + mod);
    const mix_out = (1 - mix) * low_out + mix * high_out;

    return mix_out;
}
