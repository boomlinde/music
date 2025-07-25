const std = @import("std");
const c = @import("sdl.zig").c;
const Parser = @import("Parser.zig");
const Tokenizer = @import("Tokenizer.zig");

const org = "Text Garden";

pub fn load(app: [*c]const u8, fname: [*c]const u8, comptime T: type) !T {
    const path = try getPath(app, fname, null);
    const cwd = std.fs.cwd();

    const f = cwd.openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound)
            return .{};
        return err;
    };
    defer f.close();

    var r = std.io.BufferedReader(4096, @TypeOf(f.reader())){
        .unbuffered_reader = f.reader(),
    };

    var tokenbuf: [256]u8 = undefined;

    var tokenizer = Tokenizer{
        .reader = r.reader().any(),
        .buf = &tokenbuf,
    };
    var parser = Parser{ .tokenizer = &tokenizer };

    return try parser.expect(T);
}

pub fn save(app: [*c]const u8, fname: [*c]const u8, v: anytype) !void {
    const path = try getPath(app, fname, ".tmp");
    const cwd = std.fs.cwd();

    {
        const f = try cwd.createFile(path, .{});
        defer f.close();

        var w = std.io.BufferedWriter(4096, @TypeOf(f.writer())){
            .unbuffered_writer = f.writer(),
        };

        try Parser.serialize(v, w.writer().any());
        try w.flush();
    }

    try cwd.rename(path, path[0 .. path.len - 4]);
}

fn getPath(app: [*c]const u8, fname: [*c]const u8, suffix: ?[]const u8) ![]const u8 {
    const prefpath_c = c.SDL_GetPrefPath(org, app) orelse
        return error.FailedGetPrefPath;
    return if (suffix) |suf|
        try std.fmt.bufPrint(&pathbuf, "{s}{s}{s}", .{ std.mem.span(prefpath_c), fname, suf })
    else
        return try std.fmt.bufPrint(&pathbuf, "{s}{s}", .{ std.mem.span(prefpath_c), fname });
}

var pathbuf: [std.fs.max_path_bytes]u8 = undefined;
