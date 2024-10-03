const std = @import("std");

pub fn Snapshotter(comptime T: type) type {
    return struct {
        pub fn snapshot(self: *const T) T {
            var out: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(out, field.name) = switch (@typeInfo(field.type)) {
                    .@"struct" => @field(self, field.name).snapshot(),
                    else => @atomicLoad(
                        field.type,
                        &@field(self, field.name),
                        .seq_cst,
                    ),
                };
            }
            return out;
        }
    };
}
