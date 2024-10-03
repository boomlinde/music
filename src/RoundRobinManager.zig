const List = @import("list.zig").List;
const midi = @import("midi.zig");

const RoundRobinManager = @This();

pub const Link = List(VoiceTracker).Link;

pub const VoiceTracker = struct {
    handle: usize,
    generation: usize = 0,

    fn link(self: *VoiceTracker) *Link {
        return @fieldParentPtr("value", self);
    }
};

pub const NoteOnEvent = struct { handle: usize, pitch: u7, velocity: u7 };
pub const NoteOffEvent = struct { handle: usize, pitch: u7, velocity: u7 };
pub const VoiceEvent = union(enum) {
    note_on: NoteOnEvent,
    note_off: NoteOffEvent,
};

const Ref = struct {
    generation: usize,
    voice: *VoiceTracker,

    inline fn valid(self: Ref) bool {
        return self.generation == self.voice.generation;
    }

    inline fn get(self: Ref) ?*VoiceTracker {
        return if (self.valid()) self.voice else null;
    }
};

used: List(VoiceTracker) = .{},
free: List(VoiceTracker) = .{},
keys: [128]?Ref = [_]?Ref{null} ** 128,

pub fn addLink(self: *RoundRobinManager, t: *Link) void {
    self.free.pushBack(t);
}

pub fn reset(self: *RoundRobinManager) void {
    self.used.clear();
    self.free.clear();
    for (&self.keys) |*key| key.* = null;
}

pub fn handleEvent(self: *RoundRobinManager, msg: midi.Message) ?VoiceEvent {
    return switch (msg) {
        .note_on => |d| self.noteOn(d.pitch, d.velocity),
        .note_off => |d| self.noteOff(d.pitch, d.velocity),
        else => null,
    };
}

pub fn noteOn(self: *RoundRobinManager, pitch: u7, velocity: u7) ?VoiceEvent {
    // According to MIDI, a note-on with a velocity of 0
    // represents releasing the key, so we'lll deal with this
    // as a note-off with medium velocity.
    if (velocity == 0) return self.noteOff(pitch, 64);
    if (self.isPlaying(pitch)) return null;

    const ref = self.allocateVoice() orelse return null;
    self.keys[pitch] = ref;
    return .{ .note_on = .{
        .handle = ref.voice.handle,
        .pitch = pitch,
        .velocity = velocity,
    } };
}

pub fn noteOff(self: *RoundRobinManager, pitch: u7, velocity: u7) ?VoiceEvent {
    defer self.keys[pitch] = null;

    if (self.keys[pitch]) |ref| if (ref.get()) |voice| {
        defer {
            self.used.unlink(voice.link());
            self.free.pushBack(voice.link());
        }
        return .{ .note_off = .{
            .handle = ref.voice.handle,
            .pitch = pitch,
            .velocity = velocity,
        } };
    };
    return null;
}

inline fn isPlaying(self: *RoundRobinManager, pitch: u7) bool {
    if (self.keys[pitch]) |ref| return ref.valid();
    return false;
}

inline fn allocateVoice(self: *RoundRobinManager) ?Ref {
    if (self.free.popFront()) |v| {
        v.value.generation +%= 1;
        self.used.pushBack(v);
        return .{
            .generation = v.value.generation,
            .voice = &v.value,
        };
    }

    if (self.used.popFront()) |v| {
        v.value.generation +%= 1;
        self.used.pushBack(v);
        return .{
            .generation = v.value.generation,
            .voice = &v.value,
        };
    }

    return null;
}
