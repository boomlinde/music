const std = @import("std");
const SMF = @import("SMF.zig");

const SMFStreamer = @This();

const default_tempo = @divTrunc(std.time.us_per_min, 120);

pub const Track = struct {
    current: ?*SMF.Track.Node = null,
    ticks: u28 = 0,

    fn next(self: *Track) ?SMF.Track.MTrkEvent.Event {
        const current = self.current orelse return null;
        self.current = current.next;
        return self.current.event;
    }

    fn tick(self: *Track, buf: []SMF.Track.MTrkEvent.Event, buf_idx: *usize) !void {
        defer {
            if (self.current != null) self.ticks += 1;
        }
        while (self.current) |current| {
            if (current.event.timedelta != self.ticks) return;
            if (buf_idx.* >= buf.len) return error.InsufficientEventBuf;

            buf[buf_idx.*] = current.event.event;
            buf_idx.* += 1;
            self.ticks = 0;

            self.current = current.next;
        }
    }
};

trackbuf: []Track,

time: f64 = 0,
tempo: u24 = default_tempo,
smf: ?*SMF = null,
tracks: []Track = &.{},

pub fn load(self: *SMFStreamer, smf: *SMF) !void {
    self.smf = smf;
    if (self.trackbuf.len < smf.tracks.len)
        return error.SMFStreamerTooManyTracks;
    self.tempo = default_tempo;

    // Ignore tracks that don't have any events
    var len: usize = 0;
    for (smf.tracks) |*track| {
        if (track.events) |event| {
            self.trackbuf[len] = .{ .current = event };
            len += 1;
        }
    }
    self.tracks = self.trackbuf[0..len];
    self.time = 0;
}

pub fn finished(self: *SMFStreamer) bool {
    if (self.smf == null) return true;

    for (self.tracks) |*track| {
        if (track.current != null) return false;
    }
    return true;
}

pub fn advance(self: *SMFStreamer, seconds: f64, buf: []SMF.Track.MTrkEvent.Event) ![]SMF.Track.MTrkEvent.Event {
    const smf = self.smf orelse return &.{};

    var buf_idx: usize = 0;

    self.time += seconds;
    while (self.time > SMF.secondsPerTick(self.tempo, smf.header.division)) {
        self.time -= SMF.secondsPerTick(self.tempo, smf.header.division);
        try self.tick(buf, &buf_idx);
    }

    return buf[0..buf_idx];
}

fn tick(self: *SMFStreamer, buf: []SMF.Track.MTrkEvent.Event, buf_idx: *usize) !void {
    const orig_idx = buf_idx.*;
    for (self.tracks) |*track| {
        try track.tick(buf, buf_idx);
    }

    // Update tempo if there are any tempo meta events
    for (buf[orig_idx..buf_idx.*]) |event| {
        switch (event) {
            .meta => |m| switch (m) {
                .set_tempo => |v| self.tempo = v,
                else => {},
            },
            else => {},
        }
    }
}
