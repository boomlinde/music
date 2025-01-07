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
var options = Options{};
var wait: f64 = 0;

const Options = struct {
    path: []const u8 = undefined,
    reset: ?[]const u8 = null,

    fn parse(args: []const [:0]u8) !Options {
        var out = Options{};
        var gotname = false;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--gm")) {
                out.reset = &gm_reset;
            } else if (std.mem.eql(u8, arg, "--gs")) {
                out.reset = &gs_reset;
            } else if (std.mem.eql(u8, arg, "--mt")) {
                out.reset = &mt_reset;
            } else {
                out.path = arg;
                gotname = true;
            }
        }
        if (!gotname) return error.MustSupplyPath;
        return out;
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();

    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);

    options = Options.parse(args) catch {
        try stderr.print("usage: {s} [--gs] [--gm] [--mt] <file.mid>\n", .{args[0]});
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

    while (!@atomicLoad(bool, &finished, .seq_cst)) {
        if (0 == c.jack_port_connected(midi_out))
            @atomicStore(bool, &connected, true, .seq_cst);
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

fn process(nframes: c.jack_nframes_t, _: ?*anyopaque) callconv(.C) c_int {
    const buf = c.jack_port_get_buffer(midi_out, nframes) orelse return 1;
    const samplerate: f64 = @floatFromInt(c.jack_get_sample_rate(client));
    const step = 1 / samplerate;

    c.jack_midi_clear_buffer(buf);

    // Wait for connection
    if (!@atomicLoad(bool, &connected, .seq_cst)) return 0;

    // Wait if there is a wait time
    if (wait > 0) {
        wait -= step * @as(f64, @floatFromInt(nframes));
        return 0;
    }

    for (0..nframes) |i| {
        // Send reset message if defined
        if (options.reset) |sysex| {
            if (0 != c.jack_midi_event_write(buf, @intCast(i), @ptrCast(sysex), sysex.len)) {
                std.log.err("JACK MIDI overflow", .{});
                return 0;
            }
            wait = 1;
            options.reset = null;
            return 0;
        }
        const events = streamer.advance(step, &event_buf) catch return 1;

        for (events) |ev| switch (ev) {
            .channel => |cev| switch (cev) {
                .sysex_data => {},
                inline else => |mev| {
                    const data = mev.bytes();
                    if (0 != c.jack_midi_event_write(buf, @intCast(i), &data, data.len)) {
                        std.log.err("JACK MIDI overflow", .{});
                        return 0;
                    }
                },
            },
            .escaped => |data| {
                if (0 != c.jack_midi_event_write(buf, @intCast(i), @ptrCast(data), data.len)) {
                    std.log.err("JACK MIDI overflow", .{});
                    return 0;
                }
            },
            .sysex => |data| {
                const mbuf = c.jack_midi_event_reserve(buf, @intCast(i), data.len + 1) orelse {
                    std.log.err("JACK MIDI overflow", .{});
                    return 0;
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
