const MonoVoiceManager = @This();

pub const Note = struct {
    pitch: u7,
    velocity: u7,
};

pub const State = struct {
    pitch: f32,
    gate: bool,
    velocity: f32,
};

const Link = struct {
    prev: ?u7 = null,
    next: ?u7 = null,
    velocity: u7 = 0,
};

links: [128]Link = [1]Link{.{}} ** 128,
tail: ?u7 = null,
state: State = .{ .pitch = 69, .gate = false, .velocity = 0 },

fn updateCurrent(self: *MonoVoiceManager) void {
    if (self.tail) |t| {
        self.state.pitch = @floatFromInt(t);
        self.state.velocity = @floatFromInt(self.links[t].velocity);
        self.state.gate = true;
    } else self.state.gate = false;
}

/// Start tracking a note with the given pitch and velocity
pub fn noteOn(self: *MonoVoiceManager, pitch: u7, velocity: u7) void {
    if (velocity == 0) return self.noteOff(pitch);

    // Unlink previous instance of the note if the pitch is already tracked
    self.noteOff(pitch);

    // Relink the previous tail
    self.links[pitch].prev = self.tail;
    if (self.tail) |tail| self.links[tail].next = pitch;

    // Set the velocity
    // Maintain the velocity of the last note if one
    // is already held.
    self.links[pitch].velocity = if (self.tail) |t|
        self.links[t].velocity
    else
        velocity;

    // Update the tail
    self.tail = pitch;

    self.updateCurrent();
}

/// Stop tracking a note with the given pitch
pub fn noteOff(self: *MonoVoiceManager, pitch: u7) void {
    const next = self.links[pitch].next;
    const prev = self.links[pitch].prev;

    self.links[pitch].next = null;
    self.links[pitch].prev = null;

    if (next) |n| self.links[n].prev = prev;
    if (prev) |p| self.links[p].next = next;
    if (self.tail == pitch) self.tail = prev;

    self.updateCurrent();
}

test MonoVoiceManager {
    const t = @import("std").testing;
    const Test = struct {
        var test_buf: [127]u7 = undefined;

        fn pitchSlice(manager: *MonoVoiceManager) []u7 {
            var tail = manager.tail;
            var bufidx: usize = 0;

            while (tail) |cur| {
                test_buf[bufidx] = cur;
                bufidx += 1;
                tail = manager.links[cur].prev;
            }
            return test_buf[0..bufidx];
        }
    };

    var m = MonoVoiceManager{};

    try t.expectEqual(State{ .pitch = 69, .gate = false, .velocity = 0 }, m.state);
    try t.expectEqualSlices(u7, &.{}, Test.pitchSlice(&m));

    m.noteOn(10, 123);
    try t.expectEqual(State{ .pitch = 10, .gate = true, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{10}, Test.pitchSlice(&m));

    m.noteOn(11, 101);
    try t.expectEqual(State{ .pitch = 11, .gate = true, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{ 11, 10 }, Test.pitchSlice(&m));

    m.noteOn(12, 111);
    try t.expectEqual(State{ .pitch = 12, .gate = true, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{ 12, 11, 10 }, Test.pitchSlice(&m));

    m.noteOff(12);
    try t.expectEqual(State{ .pitch = 11, .gate = true, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{ 11, 10 }, Test.pitchSlice(&m));

    m.noteOff(10);
    try t.expectEqual(State{ .pitch = 11, .gate = true, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{11}, Test.pitchSlice(&m));

    m.noteOff(11);
    try t.expectEqual(State{ .pitch = 11, .gate = false, .velocity = 123 }, m.state);
    try t.expectEqualSlices(u7, &.{}, Test.pitchSlice(&m));
}
