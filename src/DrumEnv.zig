const Accessor = @import("Accessor.zig").Accessor;

const DrumEnv = @This();
last_gate: bool = false,
state: f32 = 0,

pub const Params = struct {
    time: f32 = 0.1,
    shape: f32 = 0,

    pub usingnamespace Accessor(@This());
};

pub fn trigger(self: *DrumEnv) void {
    self.state = 1;
}

pub fn next(self: *DrumEnv, params: *const Params, srate: f32) f32 {
    const tp = params.get(.time);
    const time = tp * tp * 5;
    const shape = params.get(.shape);

    self.state = if (time != 0)
        @max(0, self.state - (1 / srate) / time)
    else
        0;

    const a: f32 = self.state * self.state;
    const b: f32 = 1 - (1 - self.state) * (1 - self.state);

    return lerp(a, b, shape);
}

inline fn lerp(a: f32, b: f32, mix: f32) f32 {
    return a * (1 - mix) + b * mix;
}
