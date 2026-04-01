const std = @import("std");

const JackState = @import("JackState.zig");
const midi = @import("midi.zig");

var in = midi.In{};
var midi_in_port: *JackState.Port = undefined;
var midi_out_port: *JackState.Port = undefined;

var done = false;

var center: ?u7 = null;

var in_ch: u4 = 0;
var left_ch: u4 = 0;
var right_ch: u4 = 1;

pub fn main() anyerror!void {
    const stderr = std.io.getStdErr().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);

    argParse(args) catch |err| {
        try stderr.print("{}\n\n", .{err});
        try stderr.print("usage: {s} <left channel 1-16> <right chennel 1-16>\n", .{args[0]});
        std.process.exit(1);
    };

    var js = try JackState.init("midisplit", cb, undefined);
    defer js.deinit();

    midi_in_port = try js.registerInput("in", JackState.DefaultMidiType);
    defer js.unregisterPort(midi_in_port);

    midi_out_port = try js.registerOutput("out", JackState.DefaultMidiType);
    defer js.unregisterPort(midi_out_port);

    try js.activate();

    // Install a signal handler to abort the process thread
    const sigaction = std.os.linux.Sigaction{
        .handler = .{ .handler = onSigint },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    if (std.os.linux.sigaction(std.os.linux.SIG.INT, &sigaction, null) != 0) {
        return error.SignalHandlerError;
    }

    while (!@atomicLoad(bool, &done, .seq_cst))
        std.time.sleep(100 * std.time.ns_per_ms);
}

fn argParse(args: []const [:0]const u8) !void {
    if (args.len != 3) return error.WrongNumberOfArguments;
    const left_big = try std.fmt.parseInt(u8, args[1], 10);
    if (left_big < 1 or left_big > 16) return error.InvalidChannelValue;
    const right_big = try std.fmt.parseInt(u8, args[2], 10);
    if (right_big < 1 or right_big > 16) return error.InvalidChannelValue;

    left_ch = @intCast(left_big - 1);
    right_ch = @intCast(right_big - 1);
}

fn onSigint(_: c_int) callconv(.C) void {
    @atomicStore(bool, &done, true, .seq_cst);
}

fn cb(nframes: JackState.NFrames, _: ?*anyopaque) callconv(.C) c_int {
    var iter = JackState.iterMidi(midi_in_port, nframes, &in) catch return 1;
    const mbuf = JackState.getMidiBuf(midi_out_port, nframes) catch return 1;
    for (0..nframes) |f| while (iter.next(@intCast(f))) |msg| {
        if (center) |c| {
            var modified = msg;
            if (msg.channel() == in_ch) switch (msg) {
                inline .note_on, .note_off => |v| {
                    if (v.pitch >= c)
                        modified.setChannel(right_ch)
                    else
                        modified.setChannel(left_ch);
                },
                inline else => modified.setChannel(right_ch),
            };
            switch (modified) {
                .sysex_data => {},
                inline else => |m| {
                    JackState.writeMidi(mbuf, @intCast(f), &m.bytes()) catch {};
                },
            }
        } else switch (msg) {
            .note_on => |v| {
                if (v.velocity == 0) center = v.pitch;
                in_ch = v.channel;
            },
            .note_off => |v| {
                center = v.pitch;
                in_ch = v.channel;
            },
            else => {},
        }
    };
    return 0;
}
