const std = @import("std");

const range = 10;

const Adsr = @This();
pub const Params = struct {
    a: f32 = 0.05,
    d: f32 = 0.5,
    s: f32 = 0.5,
    r: f32 = 0.1,

    pub usingnamespace @import("snapshotter.zig").Snapshotter(@This());
};

const Stage = enum { a, d, s, r, idle };

gate: bool = false,
stage: Stage = .idle,
output: f32 = 0,
attack_rate: f32 = 0,
decay_rate: f32 = 0,
release_rate: f32 = 0,
attack_coef: f32 = 0,
decay_coef: f32 = 0,
release_coef: f32 = 0,
sustain_level: f32 = 0,
target_ratio_a: f32 = 0,
target_ratio_dr: f32 = 0,
attack_base: f32 = 0,
decay_base: f32 = 0,
release_base: f32 = 0,

pub fn init(ashape: f32) Adsr {
    var adsr = Adsr{};
    adsr.setAttackRate(0);
    adsr.setDecayRate(0);
    adsr.setReleaseRate(0);
    adsr.setSustainLevel(1);
    adsr.setTargetRatioA(ashape);
    adsr.setTargetRatioDR(0.0001);

    return adsr;
}

fn exp(a: f32) f32 {
    return a * a * a;
}

pub fn next(self: *Adsr, params: *const Params, gate: bool, srate: f32) f32 {
    const attack_rate = exp(params.a) * range * srate;
    const decay_rate = exp(params.d) * range * srate;
    const release_rate = exp(params.r) * range * srate;

    if (gate and !self.gate) self.stage = .a;
    if (!gate and self.gate) self.stage = .r;
    self.gate = gate;

    if (attack_rate != self.attack_rate) self.setAttackRate(attack_rate);
    if (decay_rate != self.decay_rate) self.setDecayRate(decay_rate);
    if (release_rate != self.release_rate) self.setReleaseRate(release_rate);
    if (params.s != self.sustain_level) self.setSustainLevel(params.s);

    return self.process();
}

inline fn process(self: *Adsr) f32 {
    switch (self.stage) {
        .idle => {},
        .a => {
            self.output = self.attack_base + self.output * self.attack_coef;
            if (self.output >= 1) {
                self.output = 1;
                self.stage = .d;
            }
        },
        .d => {
            self.output = self.decay_base + self.output * self.decay_coef;
            if (self.output <= self.sustain_level) {
                self.output = self.sustain_level;
                self.stage = .s;
            }
        },
        .s => {},
        .r => {
            self.output = self.release_base + self.output * self.release_coef;
            if (self.output <= 0) {
                self.output = 0;
                self.stage = .idle;
            }
        },
    }
    return self.output;
}

inline fn setAttackRate(self: *Adsr, rate: f32) void {
    self.attack_rate = rate;
    self.attack_coef = calcCoef(rate, self.target_ratio_a);
    self.attack_base = (1 + self.target_ratio_a) * (1 - self.attack_coef);
}

inline fn setDecayRate(self: *Adsr, rate: f32) void {
    self.decay_rate = rate;
    self.decay_coef = calcCoef(rate, self.target_ratio_dr);
    self.decay_base = (self.sustain_level - self.target_ratio_dr) * (1 - self.decay_coef);
}

inline fn setReleaseRate(self: *Adsr, rate: f32) void {
    self.release_rate = rate;
    self.release_coef = calcCoef(rate, self.target_ratio_dr);
    self.release_base = -self.target_ratio_dr * (1 - self.release_coef);
}

inline fn setSustainLevel(self: *Adsr, level: f32) void {
    self.sustain_level = level;
    self.decay_base = (self.sustain_level - self.target_ratio_dr) * (1 - self.decay_coef);
}

inline fn setTargetRatioA(self: *Adsr, tr: f32) void {
    const target_ratio = @max(tr, 0.000000001);
    self.target_ratio_a = target_ratio;
    self.attack_coef = calcCoef(self.attack_rate, self.target_ratio_a);
    self.attack_base = (1 - self.target_ratio_a) * (1 - self.attack_coef);
}

inline fn setTargetRatioDR(self: *Adsr, tr: f32) void {
    const target_ratio = @max(tr, 0.000000001);
    self.target_ratio_dr = target_ratio;
    self.decay_coef = calcCoef(self.decay_rate, self.target_ratio_dr);
    self.release_coef = calcCoef(self.release_rate, self.target_ratio_dr);
    self.decay_base = (self.sustain_level - self.target_ratio_dr) * (1 - self.decay_coef);
    self.release_base = -self.target_ratio_dr * (1 - self.release_coef);
}

fn calcCoef(rate: f32, target_ratio: f32) f32 {
    return if (rate <= 0)
        0
    else
        @exp(-@log((1 + target_ratio) / target_ratio) / rate);
}
