const FractionalDelayLine = @This();

delay: Delay,
allpass: Allpass = .{},

pub fn feed(self: *FractionalDelayLine, in: f32) void {
    self.delay.feed(in);
}

pub fn out(self: *FractionalDelayLine, delay: f32) f32 {
    return self.allpass.next(self.delay.out(delay), delay);
}

pub fn reset(self: *FractionalDelayLine) void {
    self.delay.reset();
    self.allpass.reset();
}

const Delay = struct {
    buffer: []f32,
    idx: usize = 0,

    fn feed(self: *Delay, in: f32) void {
        self.buffer[self.idx] = in;
        self.idx = (self.idx + 1) % self.buffer.len;
    }

    fn out(self: *Delay, delay: f32) f32 {
        const integer_delay: usize = @min(@as(usize, @intFromFloat(@floor(delay))), self.buffer.len);
        const out_idx = (self.idx + self.buffer.len - integer_delay) % self.buffer.len;
        return self.buffer[out_idx];
    }

    fn reset(self: *Delay) void {
        self.* = .{ .buffer = self.buffer };
    }
};

const Allpass = struct {
    out: f32 = 0,
    in: f32 = 0,

    fn next(self: *Allpass, in: f32, delay: f32) f32 {
        const frac_delay = delay - @floor(delay);
        const coef = (1 - frac_delay) / (1 + frac_delay);
        self.out = coef * in + self.in - coef * self.out;
        self.in = in;
        return self.out;
    }

    fn reset(self: *Allpass) void {
        self.reset = 0;
    }
};
