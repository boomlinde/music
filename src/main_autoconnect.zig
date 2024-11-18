const std = @import("std");

const ArenaAllocator = @import("std").heap.ArenaAllocator;
const page_allocator = @import("std").heap.page_allocator;

const match = @import("match.zig").match;

pub const c = @cImport({
    @cInclude("jack/jack.h");
    @cInclude("jack/midiport.h");
});

const State = struct { client: *c.jack_client_t };

const Rule = struct { from: []const u8, to: []const u8 };

var rules: RuleList = undefined;

pub fn main() !void {
    var aa = ArenaAllocator.init(page_allocator);
    defer aa.deinit();

    const stdin = std.io.getStdIn().reader().any();

    rules = try RuleList.read(stdin, aa.allocator());
    defer rules.deinit();

    std.log.info("parsed {d} rules", .{rules.rules.len()});

    const client = c.jack_client_open("autoconnect", c.JackNoStartServer, null) orelse
        return error.FailedToCreateJackClient;
    defer _ = c.jack_client_close(client);

    var state: State = .{ .client = client };

    if (0 != c.jack_set_port_registration_callback(client, portRegisteredCb, &state))
        return error.FailedToSetPortRegisterCb;

    if (0 != c.jack_activate(client))
        return error.FailedToActivateClient;

    while (true) std.time.sleep(1 * std.time.ns_per_s);
}

fn portRegisteredCb(id: c.jack_port_id_t, register: c_int, arg: ?*anyopaque) callconv(.C) void {
    const state: *State = @alignCast(@ptrCast(arg));
    if (register < 1) return;

    const port = c.jack_port_by_id(state.client, id) orelse return;
    const pname = std.mem.span(c.jack_port_name(port) orelse return);

    const inputs = c.jack_get_ports(state.client, null, null, c.JackPortIsInput) orelse return;
    defer c.jack_free(@ptrCast(inputs));
    const outputs = c.jack_get_ports(state.client, null, null, c.JackPortIsOutput) orelse return;
    defer c.jack_free(@ptrCast(outputs));

    var current = rules.rules.first;
    while (current) |node| : (current = node.next) {
        const rule = node.data;
        if (match(rule.from, pname)) {
            var iter = PortIterator{ .client = state.client, .ports = inputs };
            while (iter.next()) |name| if (match(rule.to, name)) {
                std.log.info("connecting '{s}' to '{s}'", .{ pname, name });
                _ = c.jack_connect(state.client, @ptrCast(pname), @ptrCast(name));
            };
        } else if (match(rule.to, pname)) {
            var iter = PortIterator{ .client = state.client, .ports = outputs };
            while (iter.next()) |name| if (match(rule.from, name)) {
                std.log.info("connecting '{s}' to '{s}'", .{ name, pname });
                _ = c.jack_connect(state.client, @ptrCast(name), @ptrCast(pname));
            };
        }
    }
}

const PortIterator = struct {
    client: *c.jack_client_t,
    ports: [*c][*c]const u8,
    idx: usize = 0,

    fn next(self: *@This()) ?[]const u8 {
        const name = self.ports[self.idx] orelse return null;
        defer self.idx += 1;
        return std.mem.span(name);
    }
};

const RuleList = struct {
    rules: std.SinglyLinkedList(Rule) = .{},
    allocator: std.mem.Allocator,

    fn deinit(self: *RuleList) void {
        var current = self.rules.first;
        while (current) |node| {
            current = node.next;

            self.allocator.free(node.data.from);
            self.allocator.free(node.data.to);
            self.allocator.destroy(node);
        }
    }

    fn read(r: std.io.AnyReader, a: std.mem.Allocator) !RuleList {
        const Tokenizer = @import("Tokenizer.zig");
        const Parser = @import("Parser.zig");

        var list = RuleList{ .allocator = a };
        var tokenbuf: [1024]u8 = undefined;

        var t = Tokenizer{ .reader = r, .buf = &tokenbuf };
        const p = Parser{ .tokenizer = &t };

        while (try t.next()) |token| {
            if (!std.mem.eql(u8, token, "from")) {
                std.log.err("expected 'from', got '{s}'", .{token});
                return error.ExpectedFrom;
            }
            const from = try p.expectWithStringAllocator([]u8, a);
            try p.expectLiteral("to");
            const to = try p.expectWithStringAllocator([]u8, a);
            const rule_node = try a.create(std.SinglyLinkedList(Rule).Node);

            rule_node.* = .{ .data = .{ .from = from, .to = to } };
            list.rules.prepend(rule_node);
        }
        return list;
    }
};