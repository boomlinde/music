const pi = @import("std").math.pi;
const tau = @import("std").math.tau;

in_prev1: f32 = 0,
in_prev2: f32 = 0,
out_prev1: f32 = 0,
out_prev2: f32 = 0,

pub fn next(self: *@This(), in: f32, freq: f32, q: f32, srate: f32) f32 {
    const omega = tau * freq / srate;
    const alpha = @sin(omega) / (2 * if (q < 0.1) 0.01 else q);
    const a0: f32 = 1 + alpha;
    const a1: f32 = (-2 * @cos(omega)) / a0;
    const a2: f32 = (1 - alpha) / a0;

    const b0: f32 = alpha / a0;
    const b1: f32 = 0;
    const b2: f32 = -alpha / a0;

    const out = (b0 * in) + (b1 * self.in_prev1) + (b2 * self.in_prev2) - (a1 * self.out_prev1) - (a2 * self.out_prev2);

    self.in_prev2 = self.in_prev1;
    self.in_prev1 = in;
    self.out_prev2 = self.out_prev1;
    self.out_prev1 = out;

    return out * q;
}
