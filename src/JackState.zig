const std = @import("std");
const midi = @import("midi.zig");

const JackState = @This();

const ProcessCb = *const fn (nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int;

pub const c = @cImport({
    @cInclude("jack/jack.h");
    @cInclude("jack/midiport.h");
});

pub const NFrames = c.jack_nframes_t;
pub const Port = c.jack_port_t;
pub const DefaultMidiType = c.JACK_DEFAULT_MIDI_TYPE;
pub const DefaultAudioType = c.JACK_DEFAULT_AUDIO_TYPE;
pub const Sample = c.jack_default_audio_sample_t;

processCb: ProcessCb,
userdata: *anyopaque,

client: ?*c.jack_client_t,
active: bool = false,
samplerate: c.jack_nframes_t = 1,

pub fn init(name: [*c]const u8, processCb: ProcessCb, userdata: *anyopaque) !JackState {
    const client = c.jack_client_open(name, c.JackNoStartServer, null) orelse
        return error.FailedToCreateJackClient;

    const samplerate = c.jack_get_sample_rate(client);

    return .{
        .processCb = processCb,
        .userdata = userdata,

        .client = client,
        .samplerate = samplerate,
    };
}

pub fn activate(self: *JackState) !void {
    if (0 != c.jack_set_process_callback(self.client, self.processCb, @ptrCast(self)))
        return error.FailedToSetProcessCb;
    if (0 != c.jack_set_sample_rate_callback(self.client, JackState.samplerateCb, @ptrCast(self)))
        return error.FailedToSetSamplerateCb;

    if (0 != c.jack_activate(self.client))
        return error.FailedToActivateJackClient;
    self.active = true;
}

pub fn registerInput(self: *JackState, name: [*c]const u8, t: [*c]const u8) !*Port {
    return c.jack_port_register(
        self.client,
        name,
        t,
        c.JackPortIsInput,
        0,
    ) orelse error.FailedToCreateInputPort;
}

pub fn registerOutput(self: *JackState, name: [*c]const u8, t: [*c]const u8) !*Port {
    return c.jack_port_register(
        self.client,
        name,
        t,
        c.JackPortIsOutput,
        0,
    ) orelse error.FailedToCreateOutputPort;
}

pub fn unregisterPort(self: *JackState, port: *Port) void {
    _ = c.jack_port_unregister(self.client, port);
}

pub fn deinit(self: *JackState) void {
    if (self.active) {
        _ = c.jack_deactivate(self.client);
        self.active = false;
    }
    if (self.client) |client| _ = c.jack_client_close(client);
}

pub fn audioBuf(port: *Port, n: NFrames) ![*c]Sample {
    const buf = c.jack_port_get_buffer(port, n) orelse return error.BadAudioBuffer;
    return @ptrCast(@alignCast(buf));
}

pub fn iterMidi(port: *Port, nframes: NFrames, in: *midi.In) !MidiIterator {
    const buffer = c.jack_port_get_buffer(port, nframes) orelse return error.BadMidiBuffer;
    const nevents = c.jack_midi_get_event_count(buffer);

    return .{
        .count = nevents,
        .buffer = buffer,
        .in = in,
    };
}

pub fn getMidiBuf(port: *Port, nframes: NFrames) !*anyopaque {
    const buf = c.jack_port_get_buffer(port, nframes) orelse return error.BadMidiBuffer;
    c.jack_midi_clear_buffer(buf);
    return buf;
}

pub fn writeMidi(portbuf: *anyopaque, time: NFrames, data: []const u8) !void {
    const res = c.jack_midi_event_write(portbuf, time, @ptrCast(@alignCast(&data[0])), data.len);
    if (res != 0) return error.NoBuffers;
}

pub const MidiIterator = struct {
    count: NFrames,
    buffer: *anyopaque,
    in: *midi.In,
    idx: NFrames = 0,
    next_event: ?c.jack_midi_event_t = null,

    pub fn next(self: *MidiIterator, time: NFrames) ?midi.Event {
        if (self.nextRaw(time)) |bytes| for (bytes) |b| if (self.in.consume(b)) |message| {
            return message;
        };
        return null;
    }

    pub fn get(self: *MidiIterator) ?c.jack_midi_event_t {
        if (self.count == self.idx) return null;
        var ev: c.jack_midi_event_t = undefined;
        if (0 != c.jack_midi_event_get(&ev, self.buffer, self.idx))
            return null;
        self.idx += 1;
        return ev;
    }
    pub fn nextRaw(self: *MidiIterator, time: NFrames) ?[]u8 {
        if (self.next_event == null and self.idx < self.count) {
            var ev: c.jack_midi_event_t = undefined;
            if (0 != c.jack_midi_event_get(&ev, self.buffer, self.idx))
                return null;
            self.next_event = ev;
            self.idx += 1;
        }
        const ev = self.next_event orelse return null;

        if (ev.time != time) return null;

        defer self.next_event = null;
        return ev.buffer[0..ev.size];
    }
};

fn samplerateCb(srate: c.jack_nframes_t, arg: ?*anyopaque) callconv(.C) c_int {
    const self: *JackState = @ptrCast(@alignCast(arg));

    self.samplerate = srate;

    return 0;
}
