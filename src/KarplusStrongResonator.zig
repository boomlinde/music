const KarplusStrongResonator = @This();
const DCBlocker = @import("DCBlocker.zig");

const FractionalDelayLine = @import("FractionalDelayLine.zig");

delayline: FractionalDelayLine,
blocker: DCBlocker = .{},

out: f32 = 0,
meanfilter: MeanFilter = .{},

pub fn next(self: *KarplusStrongResonator, in: f32, freq: f32, srate: f32) f32 {
    const delay = srate / (freq);
    const current_delay = self.delayline.out(delay);
    const mean = self.meanfilter.next(current_delay);
    const sig = self.blocker.next(mean + in, srate);
    self.delayline.feed(sig);
    return sig;
}

const MeanFilter = struct {
    in: f32 = 0,

    fn next(self: *MeanFilter, in: f32) f32 {
        defer self.in = in;
        return 0.5 * (self.in + in);
    }
};
