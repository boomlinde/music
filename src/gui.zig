const std = @import("std");

const c = @cImport({
    @cInclude("SDL.h");
});

pub fn run(title: [*c]const u8, ww: c_int, wh: c_int, bg: RGB, fg: RGB, layout: anytype) !void {
    const margin: f32 = 0.1;

    const rows = switch (@typeInfo(@TypeOf(layout))) {
        .array => |a| a.len,
        else => @compileError("expected layout to be array"),
    };

    const columns = switch (@typeInfo(@TypeOf(layout))) {
        .array => |a| blk: {
            break :blk switch (@typeInfo(a.child)) {
                .array => |aa| aa.len,
                else => @compileError("expected layout to be array of arrays"),
            };
        },
        else => @compileError("expected layout to be array"),
    };

    if (@TypeOf(layout) != [rows][columns]Slot)
        @compileError("expected layout to be [_][_]Slot");

    var drawn: [rows][columns]f32 = [_][columns]f32{
        [_]f32{std.math.inf(f32)} ** columns,
    } ** layout.len;

    var selected: ?Slider = null;
    var selected_idx: struct { usize, usize } = .{ 0, 0 };

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS) != 0)
        return error.FailedInitSDL;
    defer c.SDL_Quit();

    const w = c.SDL_CreateWindow(
        title,
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        ww,
        wh,
        c.SDL_WINDOW_RESIZABLE,
    ) orelse return error.FailedCreatingWindow;
    defer c.SDL_DestroyWindow(w);

    const r = c.SDL_CreateRenderer(
        w,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse
        return error.FailedCreatingRenderer;
    errdefer c.SDL_DestroyRenderer(r);

    var mousecoords: struct { c_int, c_int } = .{ 0, 0 };
    var redraw_all = true;
    var ref_value: f32 = 0;

    mainloop: while (true) {
        var c_w_width: c_int = 0;
        var c_w_height: c_int = 0;
        c.SDL_GetWindowSize(w, &c_w_width, &c_w_height);
        const w_dim = Vec2{
            .x = @floatFromInt(c_w_width),
            .y = @floatFromInt(c_w_height),
        };

        const w_ratio = w_dim.div(.{
            .x = @as(f32, @floatFromInt(columns)),
            .y = @as(f32, @floatFromInt(rows)),
        });

        if (redraw_all) bg.fill(r);
        for (layout, 0..) |row, y| for (row, 0..) |slot, x| switch (slot) {
            .empty => {},
            .slider => |*s| {
                const value = s.value.get();
                if (!(redraw_all or drawn[y][x] != value)) continue;
                drawn[y][x] = value;

                const p = Vec2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

                const back = s.rect(p, w_ratio, margin);
                const inner = Rect{
                    .pos = back.pos.add(1),
                    .dim = back.dim.sub(2).mul(.{
                        .x = 1,
                        .y = (1 - value),
                    }),
                };

                const symbol_offset = back.pos.add(back.dim.mul(0.5));
                const symbol_scale = @min(back.dim.x, back.dim.y) * 0.5 * 0.5;

                (s.color orelse fg).apply(r);
                back.fill(r);
                bg.apply(r);
                inner.fill(r);
                s.symbol.draw(r, symbol_offset, symbol_scale);

                (s.color orelse fg).apply(r);
                _ = c.SDL_RenderSetClipRect(r, &inner.sdlRect());
                s.symbol.draw(r, symbol_offset, symbol_scale);
                _ = c.SDL_RenderSetClipRect(r, null);
            },
        };
        redraw_all = false;

        _ = c.SDL_RenderPresent(r);

        var ev: c.SDL_Event = undefined;
        _ = c.SDL_WaitEvent(&ev);
        while (true) {
            switch (ev.type) {
                c.SDL_QUIT => break :mainloop,
                c.SDL_MOUSEBUTTONDOWN => if (ev.button.button == c.SDL_BUTTON_LEFT) {
                    sliderloop: for (layout, 0..) |row, y| for (row, 0..) |slot, x| switch (slot) {
                        .slider => |s| {
                            ref_value = s.value.get();
                            const p = Vec2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
                            const back = s.rect(p, w_ratio, margin);
                            const mx: f32 = @floatFromInt(ev.button.x);
                            const my: f32 = @floatFromInt(ev.button.y);
                            if (mx < back.pos.x or mx >= back.pos.x + back.dim.x) continue;
                            if (my < back.pos.y or my >= back.pos.y + back.dim.y) continue;
                            selected = s;
                            selected_idx = .{ x, y };
                            _ = c.SDL_GetMouseState(&mousecoords[0], &mousecoords[1]);
                            _ = c.SDL_SetRelativeMouseMode(c.SDL_TRUE);
                            break :sliderloop;
                        },
                        else => {},
                    };
                },
                c.SDL_MOUSEBUTTONUP => if (ev.button.button == c.SDL_BUTTON_LEFT) {
                    if (selected != null) {
                        selected = null;
                        _ = c.SDL_SetRelativeMouseMode(c.SDL_FALSE);
                        c.SDL_WarpMouseInWindow(w, mousecoords[0], mousecoords[1]);
                    }
                },
                c.SDL_MOUSEMOTION => {
                    if (selected) |sel| {
                        const yrel = (0.002 / sel.h) * @as(f32, @floatFromInt(ev.motion.yrel));
                        const new_value = @max(0, @min(1, ref_value - yrel));

                        if (new_value != ref_value) {
                            sel.value.set(new_value);
                            ref_value = new_value;
                        }
                    }
                },
                c.SDL_WINDOWEVENT => redraw_all = true,
                else => {},
            }
            if (c.SDL_PollEvent(&ev) == 0) break;
        }
    }
}

pub const Slot = union(enum) {
    empty,
    slider: Slider,
};

pub const Slider = struct {
    value: Value,
    symbol: Symbol = .{},
    color: ?RGB = null,
    w: f32 = 1,
    h: f32 = 1,

    fn rect(self: Slider, p: Vec2, w_ratio: Vec2, margin: f32) Rect {
        const dim = w_ratio.mul(.{ .x = self.w, .y = self.h });
        return .{
            .pos = p.add(margin * 0.5).mul(w_ratio),
            .dim = dim.sub(w_ratio.mul(margin)),
        };
    }
};

const Rect = struct {
    pos: Vec2,
    dim: Vec2,

    pub fn fill(self: Rect, r: *c.SDL_Renderer) void {
        const sr = self.sdlRect();
        _ = c.SDL_RenderFillRect(r, &sr);
    }

    pub fn draw(self: Rect, r: *c.SDL_Renderer) void {
        const sr = self.sdlRect();
        _ = c.SDL_RenderDrawRect(r, &sr);
    }

    inline fn sdlRect(self: Rect) c.SDL_Rect {
        return c.SDL_Rect{
            .x = @intFromFloat(@floor(self.pos.x)),
            .y = @intFromFloat(@floor(self.pos.y)),
            .w = @intFromFloat(@floor(self.dim.x)),
            .h = @intFromFloat(@floor(self.dim.y)),
        };
    }
};

const Vec2 = struct {
    x: f32,
    y: f32,

    fn fromAngle(a: f32) Vec2 {
        return .{ .x = @cos(a), .y = @sin(a) };
    }

    fn add(self: Vec2, other: anytype) Vec2 {
        const vo = fromAny(other);
        return .{ .x = self.x + vo.x, .y = self.y + vo.y };
    }

    fn sub(self: Vec2, other: anytype) Vec2 {
        const vo = fromAny(other);
        return .{ .x = self.x - vo.x, .y = self.y - vo.y };
    }

    fn mul(self: Vec2, other: anytype) Vec2 {
        const vo = fromAny(other);
        return .{ .x = self.x * vo.x, .y = self.y * vo.y };
    }

    fn div(self: Vec2, other: anytype) Vec2 {
        const vo = fromAny(other);
        return .{ .x = self.x / vo.x, .y = self.y / vo.y };
    }

    inline fn fromAny(value: anytype) Vec2 {
        return switch (@typeInfo(@TypeOf(value))) {
            .@"struct" => value,
            else => .{ .x = value, .y = value },
        };
    }
};

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }

    fn apply(self: RGB, r: *c.SDL_Renderer) void {
        _ = c.SDL_SetRenderDrawColor(r, self.r, self.g, self.b, 255);
    }

    fn fill(self: RGB, r: *c.SDL_Renderer) void {
        self.apply(r);
        _ = c.SDL_RenderFillRect(r, null);
    }
};

pub const Symbol = struct {
    pub const Instruction = union(enum) {
        up,
        down,
        goto: Vec2,
    };
    pub const wedge = Symbol{ .instructions = &.{
        .{ .goto = .{ .x = 1, .y = -1 } },
        .down,
        .{ .goto = .{ .x = 1, .y = 1 } },
        .{ .goto = .{ .x = -1, .y = 1 } },
        .{ .goto = .{ .x = 1, .y = -1 } },
    } };
    pub const saw_wave = Symbol{ .instructions = &.{
        .{ .goto = .{ .x = -1, .y = 1 } },
        .down,
        .{ .goto = .{ .x = -1, .y = -1 } },
        .{ .goto = .{ .x = 1, .y = 1 } },
    } };
    pub const square_wave = Symbol{ .instructions = &.{
        .{ .goto = .{ .x = -1, .y = -1 } },
        .down,
        .{ .goto = .{ .x = 0, .y = -1 } },
        .{ .goto = .{ .x = 0, .y = 1 } },
        .{ .goto = .{ .x = 1, .y = 1 } },
    } };
    pub const triangle_wave = Symbol{ .instructions = &.{
        .{ .goto = .{ .x = -1, .y = 0 } },
        .down,
        .{ .goto = .{ .x = -0.5, .y = -1 } },
        .{ .goto = .{ .x = 0.5, .y = 1 } },
        .{ .goto = .{ .x = 1, .y = 0 } },
    } };
    pub const sine_wave = Symbol{ .instructions = &sine(64) };
    pub const triangle = Symbol{ .instructions = &ngon(3, -0.25) };
    pub const diamond = Symbol{ .instructions = &ngon(4, 0) };
    pub const square = Symbol{ .instructions = &ngon(4, -0.125) };
    pub const pentagon = Symbol{ .instructions = &ngon(5, -0.05) };
    pub const hexagon = Symbol{ .instructions = &ngon(6, 0) };
    pub const circle = Symbol{ .instructions = &ngon(32, 0) };

    instructions: []const Instruction = &.{},

    fn draw(self: Symbol, r: *c.SDL_Renderer, offset: Vec2, scale: f32) void {
        var down = false;
        var pos = Vec2{ .x = 0, .y = 0 };
        for (self.instructions) |ins| switch (ins) {
            .up => down = false,
            .down => down = true,
            .goto => |newpos| {
                if (down) {
                    const a = pos.mul(scale).add(offset);
                    const b = newpos.mul(scale).add(offset);
                    _ = c.SDL_RenderDrawLine(
                        r,
                        @intFromFloat(@round(a.x)),
                        @intFromFloat(@round(a.y)),
                        @intFromFloat(@round(b.x)),
                        @intFromFloat(@round(b.y)),
                    );
                }
                pos = newpos;
            },
        };
    }

    fn sine(comptime n: usize) [n + 3]Instruction {
        var out: [n + 3]Instruction = undefined;
        out[0] = .{ .goto = .{ .x = -1, .y = 0 } };
        out[1] = .down;

        for (0..n + 1) |i| {
            const phase: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const x = 2 * phase - 1;
            out[i + 2] = .{ .goto = .{ .x = x, .y = -@sin(phase * std.math.tau) } };
        }
        return out;
    }
    fn ngon(comptime n: usize, comptime angle_offset: f32) [n + 2]Instruction {
        if (n < 2) @compileError("ngon must have at least 2 corners");

        var arr: [n + 2]Instruction = undefined;
        arr[0] = .{ .goto = Vec2.fromAngle(std.math.tau * angle_offset) };
        arr[1] = .down;

        const f_n: f32 = @floatFromInt(n);
        for (0..n) |i| {
            const f_i: f32 = @floatFromInt(i + 1);
            arr[i + 2] = .{ .goto = Vec2.fromAngle(std.math.tau * (angle_offset + f_i / f_n)) };
        }

        return arr;
    }
};

pub const Value = struct {
    const SetFunction = *const fn (value: f32, arg: *anyopaque) void;
    const GetFunction = *const fn (arg: *anyopaque) f32;

    setter: SetFunction,
    getter: GetFunction,
    arg: *anyopaque,

    pub fn set(self: Value, value: f32) void {
        self.setter(value, self.arg);
    }

    pub fn get(self: Value) f32 {
        return self.getter(self.arg);
    }

    pub fn int(comptime T: type, vp: *T) Value {
        const max_int = std.math.maxInt(T);
        const wrap = struct {
            fn setter(value: f32, arg: *anyopaque) void {
                const ip: *T = @ptrCast(@alignCast(arg));
                const integer: T = @intFromFloat(@floor(value * max_int));
                @atomicStore(T, ip, integer, .seq_cst);
            }

            fn getter(arg: *anyopaque) f32 {
                const ip: *T = @ptrCast(@alignCast(arg));
                return @as(f32, @floatFromInt(@atomicLoad(T, ip, .seq_cst))) / max_int;
            }
        };
        return .{
            .setter = wrap.setter,
            .getter = wrap.getter,
            .arg = @ptrCast(vp),
        };
    }

    pub fn passthrough(vp: *f32) Value {
        const wrap = struct {
            fn setter(value: f32, arg: *anyopaque) void {
                const fp: *f32 = @ptrCast(@alignCast(arg));
                @atomicStore(f32, fp, value, .seq_cst);
            }
            fn getter(arg: *anyopaque) f32 {
                const fp: *f32 = @ptrCast(@alignCast(arg));
                return @atomicLoad(f32, fp, .seq_cst);
            }
        };
        return .{
            .setter = wrap.setter,
            .getter = wrap.getter,
            .arg = @ptrCast(vp),
        };
    }
};
