const std = @import("std");
const JackState = @import("JackState.zig");

const default_rate = 0.25;

var midiport: *JackState.Port = undefined;
var rate: f64 = undefined;
var time: f64 = undefined;
var js: JackState = undefined;

pub fn main() !void {
    const name = "Active sensing test";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    js = try JackState.init(name, cb, undefined);
    defer js.deinit();

    midiport = try js.registerOutput("out", JackState.DefaultMidiType);

    rate = try getRate(gpa.allocator());
    time = rate;

    try js.activate();
    while (true) std.time.sleep(1 * std.time.ns_per_s);
}

fn cb(nframes: JackState.NFrames, jstate_opaque: ?*anyopaque) callconv(.C) c_int {
    _ = jstate_opaque;

    const midibuf = JackState.getMidiBuf(midiport, nframes) catch return 1;

    for (0..nframes) |frame| {
        if (time >= rate) {
            JackState.writeMidi(midibuf, @intCast(frame), &.{0xfe}) catch {
                std.debug.print("error: {d} {}\n", .{ time, frame });
            };
            time -= rate;
        }
        time += 1 / @as(f64, @floatFromInt(js.samplerate));
    }

    return 0;
}

fn getRate(allocator: std.mem.Allocator) !f64 {
    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();

    // skip arg 0
    if (!iter.skip()) return error.NoArguments;

    const rate_str = iter.next() orelse return default_rate;

    return std.fmt.parseFloat(f64, rate_str);
}
