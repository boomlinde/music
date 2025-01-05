const std = @import("std");
const vlq = @import("vlq.zig");
const midi = @import("midi.zig");

const PeekReader = @import("PeekReader.zig");

const SMF = @This();

pub const Header = struct {
    const id = "MThd";
    pub const Format = enum {
        single,
        simultaneous,
        sequential,
        fn fromInt(int: u16) !Format {
            return switch (int) {
                0 => .single,
                1 => .simultaneous,
                2 => .sequential,
                else => error.InvalidFormat,
            };
        }

        fn toInt(self: Format) u16 {
            return switch (self) {
                .single => 0,
                .simultaneous => 1,
                .sequential => 2,
            };
        }
    };
    pub const Division = union(enum) {
        metrical: u15,
        timecode: struct { format: i7, ticks: u8 },

        fn fromInt(int: u16) !Division {
            switch (int >> 15) {
                0 => return .{ .metrical = @intCast(int & 0x7fff) },
                1 => {
                    const format: i7 = @bitCast(@as(u7, @intCast((int >> 8) & 0x7f)));
                    switch (format) {
                        -24, -25, -29, -30 => {},
                        else => return error.InvalidSMPTEFormat,
                    }
                    return .{ .timecode = .{
                        .ticks = @intCast(int & 0xff),
                        .format = format,
                    } };
                },
                else => unreachable,
            }
        }

        fn toInt(self: Division) u16 {
            switch (self) {
                .metrical => |ticks| return @intCast(ticks),
                .timecode => |v| {
                    const uformat: u7 = @bitCast(v.format);
                    return 0x8000 | v | (@as(u16, uformat) << 8);
                },
            }
        }
    };
    format: Format,
    division: Division,

    fn decode(r: std.io.AnyReader, length: u32, ntrks: *u16) !Header {
        if (length < 6) return error.InvalidHeader;
        const format = try Format.fromInt(try r.readInt(u16, .big));
        ntrks.* = try r.readInt(u16, .big);
        const division = try Division.fromInt(try r.readInt(u16, .big));

        if (format == .single and ntrks.* != 1) return error.Format0MustHaveOneTrack;

        // skip any remaining header bytes
        if (length != 6) try r.skipBytes(length - 6, .{});

        return .{ .format = format, .division = division };
    }
};

pub const Track = struct {
    const id = "MTrk";
    pub const MTrkEvent = struct {
        pub const Event = union(enum) {
            pub const Meta = union(enum) {
                pub const SMPTEOffset = struct {
                    hours: u8,
                    minutes: u8,
                    seconds: u8,
                    frames: u8,
                    fractional_frames: u8,
                };

                pub const TimeSignature = struct {
                    numerator: u8,
                    denominator: u8,
                    clocks: u8,
                    demisemiquavers: u8,
                };

                pub const KeySignature = struct {
                    flats: i8,
                    minor: bool,
                };

                sequence_number: u16,
                text: []u8,
                copyright: []u8,
                track_name: []u8,
                instrument_name: []u8,
                lyric: []u8,
                marker: []u8,
                cue_point: []u8,
                channel_prefix: u4,
                end_of_track,
                set_tempo: u24,
                smpte_offset: SMPTEOffset,
                time_signature: TimeSignature,
                key_signature: KeySignature,
                sequencer: []u8,
                unknown: []u8,

                fn deinit(self: Meta, allocator: std.mem.Allocator) void {
                    switch (self) {
                        .text,
                        .copyright,
                        .track_name,
                        .instrument_name,
                        .lyric,
                        .marker,
                        .cue_point,
                        .sequencer,
                        .unknown,
                        => |v| {
                            allocator.free(v);
                        },
                        else => {},
                    }
                }

                fn decode(r: std.io.AnyReader, allocator: std.mem.Allocator) !Meta {
                    const t = try r.readByte();
                    const len = try vlq.decode(r);

                    switch (t) {
                        0x00 => { // sequence number
                            if (len != 2) return error.InvalidSequenceNumberLength;
                            return .{ .sequence_number = try r.readInt(u16, .big) };
                        },
                        0x01 => { // text
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .text = buf };
                        },
                        0x02 => { // copyright
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .copyright = buf };
                        },
                        0x03 => { // track name
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .track_name = buf };
                        },
                        0x04 => { // instrument name
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .instrument_name = buf };
                        },
                        0x05 => { // lyric
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .lyric = buf };
                        },
                        0x06 => { // marker
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .marker = buf };
                        },
                        0x07 => { // cue point
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .cue_point = buf };
                        },
                        0x20 => { // channel prefix
                            if (len != 1) return error.InvalidChannelPrefixLength;
                            const ch = try r.readByte();
                            return .{ .channel_prefix = @intCast(ch & 0xf) };
                        },
                        0x2f => { // end of track
                            if (len != 0) return error.InvalidEndOfTrackLength;
                            return .end_of_track;
                        },
                        0x51 => { // set tempo
                            if (len != 3) return error.InvalidSetTempoLength;
                            return .{ .set_tempo = try r.readInt(u24, .big) };
                        },
                        0x54 => { // smpte offset
                            if (len != 5) return error.InvalidSMPTEOffsetLength;
                            const hours = try r.readByte();
                            const minutes = try r.readByte();
                            const seconds = try r.readByte();
                            const frames = try r.readByte();
                            const fractional_frames = try r.readByte();
                            return .{ .smpte_offset = .{
                                .hours = hours,
                                .minutes = minutes,
                                .seconds = seconds,
                                .frames = frames,
                                .fractional_frames = fractional_frames,
                            } };
                        },
                        0x58 => { // time signature
                            if (len != 4) return error.InvalidTimeSignatureLength;
                            const numerator = try r.readByte();
                            const denominator = try r.readByte();
                            const clocks = try r.readByte();
                            const demisemiquavers = try r.readByte();

                            return .{ .time_signature = .{
                                .numerator = numerator,
                                .denominator = denominator,
                                .clocks = clocks,
                                .demisemiquavers = demisemiquavers,
                            } };
                        },

                        0x59 => { // key signature
                            if (len != 2) return error.InvalidKeySignatureLength;
                            const flats = try r.readByteSigned();
                            const minor_int = try r.readByteSigned();
                            const minor = switch (minor_int) {
                                0 => false,
                                1 => true,
                                else => return error.InvalidKeySignatureMinorFlagValue,
                            };

                            return .{ .key_signature = .{ .flats = flats, .minor = minor } };
                        },
                        0x7f => { // sequencer
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .sequencer = buf };
                        },
                        else => { // Skip unknown meta events
                            const buf = try allocator.alloc(u8, len);
                            errdefer allocator.free(buf);
                            _ = try r.readAtLeast(buf, len);
                            return .{ .unknown = buf };
                        },
                    }
                }
            };
            channel: midi.Event,
            sysex: []u8,
            escaped: []u8,
            meta: Meta,

            fn deinit(self: Event, allocator: std.mem.Allocator) void {
                switch (self) {
                    .channel => {},
                    .sysex => |v| allocator.free(v),
                    .escaped => |v| allocator.free(v),
                    .meta => |v| v.deinit(allocator),
                }
            }
        };
        timedelta: u28,
        event: Event,

        fn deinit(self: MTrkEvent, allocator: std.mem.Allocator) void {
            self.event.deinit(allocator);
        }

        fn decode(sr: std.io.AnyReader, mp: *midi.In, a: std.mem.Allocator) !MTrkEvent {
            var pr = PeekReader{ .r = sr };
            const r = pr.reader().any();

            const timedelta = try vlq.decode(r);

            switch (try pr.peek() orelse return error.PeekEOF) {
                0xf0 => { // sysex
                    try pr.drop();
                    const len = try vlq.decode(r);
                    const buf = try a.alloc(u8, len);
                    return .{
                        .timedelta = timedelta,
                        .event = .{ .sysex = buf },
                    };
                },
                0xf7 => { // escaped
                    try pr.drop();
                    const len = try vlq.decode(r);
                    const buf = try a.alloc(u8, len);
                    return .{
                        .timedelta = timedelta,
                        .event = .{ .escaped = buf },
                    };
                },
                0xff => { // meta
                    try pr.drop();
                    const meta_ev = try MTrkEvent.Event.Meta.decode(r, a);
                    return .{
                        .timedelta = timedelta,
                        .event = .{ .meta = meta_ev },
                    };
                },
                else => |b| { // channel
                    if (b >= 0xf0) return error.InvalidChannelEvent;
                    for (0..3) |_| {
                        const packet = try r.readByte();
                        if (mp.consume(packet)) |ev| {
                            return .{
                                .timedelta = timedelta,
                                .event = .{ .channel = ev },
                            };
                        }
                    }
                    return error.FailedToParseMidiEvent;
                },
            }
        }
    };

    const Node = struct {
        event: MTrkEvent,
        next: ?*Node = null,
    };
    events: ?*Node = null,

    fn decode(sr: std.io.AnyReader, len: usize, a: std.mem.Allocator) !Track {
        var lr = std.io.limitedReader(sr, len);
        const r = lr.reader().any();
        var mp = midi.In{};

        var tail: ?*Node = null;

        var track = Track{};
        errdefer track.deinit(a);

        while (lr.bytes_left != 0) {
            const event = try MTrkEvent.decode(r, &mp, a);
            const node = try a.create(Node);
            node.* = .{ .event = event };

            if (tail) |t| {
                t.next = node;
            } else track.events = node;
            tail = node;
        }

        return track;
    }

    fn deinit(self: *Track, allocator: std.mem.Allocator) void {
        while (self.events) |node| {
            node.event.deinit(allocator);
            self.events = node.next;
            allocator.destroy(node);
        }
    }
};

header: Header,
tracks: []Track,

pub fn decode(r: std.io.AnyReader, allocator: std.mem.Allocator) !SMF {
    var id: [4]u8 = undefined;

    var ntrks: u16 = undefined;
    var header: ?Header = null;
    var tracks: ?[]Track = null;
    var trackidx: usize = 0;

    errdefer {
        if (tracks) |t| {
            for (0..trackidx) |idx| t[idx].deinit(allocator);
            allocator.free(t);
        }
    }

    while (true) {
        const idlen = try r.read(&id);
        if (idlen == 0) break;
        if (idlen != 4) return error.UnexpectedEOF;
        const len = try r.readInt(u32, .big);

        if (std.mem.eql(u8, Header.id, &id)) {
            header = try Header.decode(r, len, &ntrks);
            tracks = try allocator.alloc(Track, ntrks);
        } else if (std.mem.eql(u8, Track.id, &id)) {
            if (header == null) return error.TrackChunkAppearedBeforeHeaderChunk;
            if (trackidx == ntrks) return error.TooManyTrackChunks;
            const t = tracks orelse unreachable;
            t[trackidx] = try Track.decode(r, len, allocator);
            trackidx += 1;
        } else {
            try r.skipBytes(len, .{});
            std.log.debug("skipping unknown chunk {s}", .{&id});
        }
    }

    if (header) |h| if (tracks) |t| return .{ .header = h, .tracks = t };

    return error.MissingHeader;
}

pub fn deinit(self: *SMF, allocator: std.mem.Allocator) void {
    for (self.tracks) |*track| track.deinit(allocator);
    allocator.free(self.tracks);
}

test decode {
    const data = @embedFile("testdata/BWV599.mid");
    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = data,
    };

    var smf = try decode(stream.reader().any(), std.testing.allocator);
    defer smf.deinit(std.testing.allocator);

    std.debug.print("{any}\n", .{smf.header});
    for (smf.tracks, 0..) |track, i| {
        std.debug.print("begin track {}\n", .{i});
        var current = track.events;
        while (current) |node| {
            std.debug.print("{any}\n", .{node.event});
            current = node.next;
        }
        std.debug.print("end track {}\n", .{i});
    }
}
