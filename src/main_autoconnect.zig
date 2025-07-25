const std = @import("std");

const match = @import("match.zig").match;

pub const c = @cImport({
    @cInclude("jack/jack.h");
    @cInclude("jack/midiport.h");
});

const State = struct { client: *c.jack_client_t };

const RuleType = enum { connect, disconnect, reconnect };
const Rule = struct { src: []const u8, dst: []const u8 };

var rules: RuleList = undefined;
var mtime: i128 = -1;
var cfgpath: []u8 = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    rules = .{ .allocator = gpa.allocator() };
    defer rules.deinit();

    cfgpath = try getConfigFilename(gpa.allocator());
    defer gpa.allocator().free(cfgpath);

    mtime = (try std.fs.cwd().statFile(cfgpath)).mtime;
    const rulefile = try std.fs.cwd().openFile(cfgpath, .{});
    const r = rulefile.reader().any();

    rules = try RuleList.read(r, gpa.allocator());

    std.log.info("parsed {d} rules", .{rules.connect.len() + rules.disconnect.len()});

    const client = c.jack_client_open("autoconnect", c.JackNoStartServer, null) orelse
        return error.FailedToCreateJackClient;
    defer _ = c.jack_client_close(client);

    var state: State = .{ .client = client };

    if (0 != c.jack_set_port_registration_callback(client, portRegisteredCb, &state))
        return error.FailedToSetPortRegisterCb;

    if (0 != c.jack_set_port_connect_callback(client, portConnectedCb, &state))
        return error.FailedToSetPortConnectCb;

    if (0 != c.jack_activate(client))
        return error.FailedToActivateClient;

    while (true) std.time.sleep(1 * std.time.ns_per_s);
}

fn maybeReloadRules() !void {
    const current_mtime = (try std.fs.cwd().statFile(cfgpath)).mtime;
    if (mtime == current_mtime) return;

    mtime = current_mtime;
    const rulefile = try std.fs.cwd().openFile(cfgpath, .{});
    defer rulefile.close();

    const r = rulefile.reader().any();

    rules.deinit();
    rules = try RuleList.read(r, rules.allocator);
    std.log.info("parsed {d} rules", .{rules.connect.len() + rules.disconnect.len()});
}

fn getConfigFilename(a: std.mem.Allocator) ![]u8 {
    var iter = try std.process.argsWithAllocator(a);
    defer iter.deinit();

    // skip arg 0
    if (!iter.skip()) return error.NoArguments;

    const name = iter.next() orelse {
        std.log.err("must supply config path", .{});
        return error.NoFileName;
    };

    const name_dupe = try a.dupe(u8, name);
    errdefer a.free(name_dupe);

    if (iter.next() != null) {
        std.log.err("too many arguments", .{});
        return error.TooManyArgs;
    }

    return name_dupe;
}

fn portConnectedCb(a: c.jack_port_id_t, b: c.jack_port_id_t, connect: c_int, arg: ?*anyopaque) callconv(.C) void {
    const state: *State = @alignCast(@ptrCast(arg));

    if (connect == 0) return;

    maybeReloadRules() catch |err| {
        std.log.err("failed to reload rules: {}", .{err});
    };

    const aport = c.jack_port_by_id(state.client, a) orelse return;
    const aname = std.mem.span(c.jack_port_name(aport) orelse return);
    const bport = c.jack_port_by_id(state.client, b) orelse return;
    const bname = std.mem.span(c.jack_port_name(bport) orelse return);

    // Check whether any of the connect rules match
    // Don't disconnect if there is
    var current = rules.connect.first;
    while (current) |node| : (current = node.next) {
        const rule = node.data;
        if (match(rule.src, aname) and match(rule.dst, bname)) return;
        if (match(rule.src, bname) and match(rule.dst, aname)) return;
    }

    // Disconnect if any matching disconnect rules are found
    current = rules.disconnect.first;
    while (current) |node| : (current = node.next) {
        const rule = node.data;
        var matched: bool = false;
        if (match(rule.src, aname) and match(rule.dst, bname)) matched = true;
        if (match(rule.src, bname) and match(rule.dst, aname)) matched = true;

        if (matched) {
            if ((c.jack_port_flags(aport) & c.JackPortIsOutput) != 0) {
                std.log.info("disconnecting '{s}' from '{s}'", .{ aname, bname });
                _ = c.jack_disconnect(state.client, aname, bname);
            } else {
                std.log.info("disconnecting '{s}' from '{s}'", .{ bname, aname });
                _ = c.jack_disconnect(state.client, bname, aname);
            }

            return;
        }
    }
}
fn portRegisteredCb(id: c.jack_port_id_t, register: c_int, arg: ?*anyopaque) callconv(.C) void {
    const state: *State = @alignCast(@ptrCast(arg));
    if (register < 1) return;

    maybeReloadRules() catch |err| {
        std.log.err("failed to reload rules: {}", .{err});
    };

    const port = c.jack_port_by_id(state.client, id) orelse return;
    const pname = std.mem.span(c.jack_port_name(port) orelse return);

    const inputs = c.jack_get_ports(state.client, null, null, c.JackPortIsInput) orelse return;
    defer c.jack_free(@ptrCast(inputs));
    const outputs = c.jack_get_ports(state.client, null, null, c.JackPortIsOutput) orelse return;
    defer c.jack_free(@ptrCast(outputs));

    var current = rules.connect.first;
    while (current) |node| : (current = node.next) {
        const rule = node.data;
        if (match(rule.src, pname)) {
            var iter = PortIterator{ .client = state.client, .ports = inputs };
            while (iter.next()) |name| if (match(rule.dst, name)) {
                std.log.info("connecting '{s}' to '{s}'", .{ pname, name });
                _ = c.jack_connect(state.client, @ptrCast(pname), @ptrCast(name));
            };
        } else if (match(rule.dst, pname)) {
            var iter = PortIterator{ .client = state.client, .ports = outputs };
            while (iter.next()) |name| if (match(rule.src, name)) {
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
    connect: std.SinglyLinkedList(Rule) = .{},
    disconnect: std.SinglyLinkedList(Rule) = .{},
    allocator: std.mem.Allocator,

    fn deinit(self: *RuleList) void {
        var current = self.connect.first;
        while (current) |node| {
            current = node.next;

            self.allocator.free(node.data.src);
            self.allocator.free(node.data.dst);
            self.allocator.destroy(node);
        }

        current = self.disconnect.first;
        while (current) |node| {
            current = node.next;

            self.allocator.free(node.data.src);
            self.allocator.free(node.data.dst);
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
            var isconnect: bool = false;
            if (std.mem.eql(u8, token, "connect")) {
                isconnect = true;
            } else if (std.mem.eql(u8, token, "disconnect")) {
                isconnect = false;
            } else {
                std.log.err("expected 'connect' or 'disconnect', got '{s}'", .{token});
                return error.ExpectedType;
            }

            const src = try p.expectWithStringAllocator([]u8, a);
            if (isconnect)
                try p.expectLiteral("to")
            else
                try p.expectLiteral("from");
            const dst = try p.expectWithStringAllocator([]u8, a);

            const rule_node = try a.create(std.SinglyLinkedList(Rule).Node);

            rule_node.* = .{ .data = .{ .src = src, .dst = dst } };

            if (isconnect)
                list.connect.prepend(rule_node)
            else
                list.disconnect.prepend(rule_node);
        }
        return list;
    }
};
