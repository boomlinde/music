const std = @import("std");

const SMF = @import("SMF.zig");
const SMFStreamer = @import("SMFStreamer.zig");
const midi = @import("midi.zig");

const gs_reset = [_]u8{ 0xf0, 0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7f, 0x00, 0x41, 0xf7 };
const gm_reset = [_]u8{ 0xf0, 0x7e, 0x7f, 0x09, 0x01, 0xf7 };
const mt_reset = [_]u8{ 0xf0, 0x41, 0x10, 0x16, 0x12, 0x7f, 0x00, 0x00, 0x00, 0x7f, 0x00, 0xf7 };

const c = @cImport({
    @cInclude("jack/jack.h");
    @cInclude("jack/midiport.h");
});

var event_buf: [1024 * 1024]SMF.Track.MTrkEvent.Event = undefined;
var track_buf: [256]SMFStreamer.Track = undefined;
var smf: SMF = undefined;
var streamer = SMFStreamer{ .trackbuf = &track_buf };

var client: *c.jack_client_t = undefined;
var midi_out: *c.jack_port_t = undefined;

var finished = false;
var connected = false;
var wait: f64 = 0;
var abort: bool = false;
var aborted: bool = false;

var options = struct {
    path: []const u8 = undefined,
    reset: ?[]const u8 = null,
    resetcc: bool = true,

    fn parse(this: *@This(), args: []const [:0]u8) !void {
        var gotname = false;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--gm")) {
                this.reset = &gm_reset;
            } else if (std.mem.eql(u8, arg, "--gs")) {
                this.reset = &gs_reset;
            } else if (std.mem.eql(u8, arg, "--mt")) {
                this.reset = &mt_reset;
            } else if (std.mem.eql(u8, arg, "--noresetcc")) {
                this.resetcc = false;
            } else {
                if (gotname) return error.TooManyPaths;
                this.path = arg;
                gotname = true;
            }
        }
        if (!gotname) return error.MustSupplyPath;
    }
}{};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();

    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);

    options.parse(args) catch {
        try stderr.print("usage: {s} [--gs] [--gm] [--mt] [--noresetcc] <file.mid>\n", .{args[0]});
        std.process.exit(1);
    };

    const file = try std.fs.cwd().openFile(options.path, .{});

    smf = try SMF.decode(file.reader().any(), a);
    defer smf.deinit(a);
    try streamer.load(&smf);

    client = c.jack_client_open(
        "smfplay",
        c.JackNoStartServer,
        null,
    ) orelse return error.FailedOpenJackClient;
    defer _ = c.jack_client_close(client);

    midi_out = c.jack_port_register(
        client,
        "out",
        c.JACK_DEFAULT_MIDI_TYPE,
        c.JackPortIsOutput,
        0,
    ) orelse return error.FailedRegisterJackPort;
    defer _ = c.jack_port_unregister(client, midi_out);

    if (0 != c.jack_set_process_callback(client, &process, null)) {
        return error.FailedJackSetProcessCallback;
    }

    if (0 != c.jack_activate(client)) {
        return error.FailedActivateJackClient;
    }
    defer _ = c.jack_deactivate(client);

    // Install a signal handler to abort the process thread
    const sigaction = std.os.linux.Sigaction{
        .handler = .{ .handler = onSigint },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    if (std.os.linux.sigaction(std.os.linux.SIG.INT, &sigaction, null) != 0) {
        return error.SignalHandlerError;
    }

    while (!@atomicLoad(bool, &finished, .seq_cst) and !@atomicLoad(bool, &aborted, .seq_cst)) {
        if (0 == c.jack_port_connected(midi_out))
            @atomicStore(bool, &connected, true, .seq_cst);
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

fn onSigint(_: c_int) callconv(.C) void {
    @atomicStore(bool, &abort, true, .seq_cst);
}

fn process(nframes: c.jack_nframes_t, _: ?*anyopaque) callconv(.C) c_int {
    const buf = c.jack_port_get_buffer(midi_out, nframes) orelse return 1;
    const samplerate: f64 = @floatFromInt(c.jack_get_sample_rate(client));
    const step = 1 / samplerate;

    c.jack_midi_clear_buffer(buf);

    // Do nothing if aborted
    if (@atomicLoad(bool, &aborted, .seq_cst)) return 0;

    // Wait for connection
    if (!@atomicLoad(bool, &connected, .seq_cst)) return 0;

    // Wait if there is a wait time
    if (wait > 0) {
        wait -= step * @as(f64, @floatFromInt(nframes));
        return 0;
    }

    for (0..nframes) |i| {
        // All notes off if abort and sustain off
        if (@atomicLoad(bool, &abort, .seq_cst)) {
            // Signal that we've fulfilled the abortion request
            @atomicStore(bool, &aborted, true, .seq_cst);

            for (0..16) |ch| {
                const msg = midi.Event.ControlChange{
                    .channel = @intCast(ch),
                    .controller = 0x7b,
                    .value = 0,
                };
                const bytes = msg.bytes();
                writeEvent(buf, i, &bytes) catch return 1;
            }

            return 0;
        }

        // Send reset message if defined
        if (options.reset) |sysex| {
            options.reset = null;
            writeEvent(buf, i, sysex) catch return 1;
            wait = 1;
            return 0;
        }

        // Reset all controllers if resetcc
        if (options.resetcc) {
            options.resetcc = false;
            for (0..16) |ch| {
                const msg = midi.Event.ControlChange{
                    .channel = @intCast(ch),
                    .controller = 0x71,
                    .value = 0,
                };
                const bytes = msg.bytes();
                writeEvent(buf, i, &bytes) catch return 1;
            }
            wait = 0.1;
            return 0;
        }

        const events = streamer.advance(step, &event_buf) catch return 1;
        for (events) |ev| switch (ev) {
            .channel => |cev| switch (cev) {
                .sysex_data => {},
                inline else => |mev| {
                    const bytes = mev.bytes();

                    writeEvent(buf, i, &bytes) catch return 1;
                },
            },
            .escaped => |data| {
                writeEvent(buf, i, data) catch return 1;
            },
            .sysex => |data| {
                const mbuf = c.jack_midi_event_reserve(buf, @intCast(i), data.len + 1) orelse {
                    std.log.err("JACK MIDI overflow", .{});
                    return 1;
                };

                mbuf[0] = 0xf0;
                for (data, 1..) |b, idx| mbuf[idx] = b;
            },
            else => {},
        };
    }

    if (streamer.finished()) @atomicStore(bool, &finished, true, .seq_cst);
    return 0;
}

fn writeEvent(buf: *anyopaque, i: usize, data: []const u8) !void {
    if (0 != c.jack_midi_event_write(buf, @intCast(i), @ptrCast(data), data.len)) {
        std.log.err("JACK MIDI overflow", .{});
        return error.JackMidiBufferOverflow;
    }
}
