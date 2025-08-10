const MonoVoiceManager = @import("MonoVoiceManager.zig");
const Smoother = @import("Smoother.zig");

const MonoLegato = @This();

time: f32,
smoother: Smoother = .{},
gate: bool = false,

pub fn next(self: *MonoLegato, in: MonoVoiceManager.State, srate: f32) MonoVoiceManager.State {
    defer self.gate = in.gate;
    if (in.gate and !self.gate) self.smoother.short(in.pitch);

    return .{
        .pitch = self.smoother.next(in.pitch, self.time, srate),
        .gate = in.gate,
        .velocity = in.velocity,
    };
}
