const std = @import("std");

pub fn Accessor(comptime T: type) type {
    const E = FieldEnum(T);

    return struct {
        pub inline fn get(self: *const T, comptime field: E) FieldType(T, field) {
            const FT = FieldType(T, field);
            return @atomicLoad(FT, &@field(self, @tagName(field)), .seq_cst);
        }

        pub inline fn set(self: *T, comptime field: E, value: FieldType(T, field)) void {
            const FT = FieldType(T, field);
            @atomicStore(FT, &@field(self, @tagName(field)), value, .seq_cst);
        }
    };
}

test Accessor {
    const t = std.testing;

    const Struct = struct {
        a: f32 = 0,
        b: u8 = 1,
        c: usize = 2,

        pub usingnamespace Accessor(@This());
    };
    var v = Struct{};

    try t.expectEqual(0, v.get(.a));
    try t.expectEqual(1, v.get(.b));
    try t.expectEqual(2, v.get(.c));

    v.set(.a, 31.5);
    v.set(.b, 255);
    v.set(.c, 555);

    try t.expectEqual(31.5, v.get(.a));
    try t.expectEqual(255, v.get(.b));
    try t.expectEqual(555, v.get(.c));
}

pub fn FieldEnum(comptime Struct: type) type {
    const struct_fields = std.meta.fields(Struct);
    var enum_fields: [struct_fields.len]std.builtin.Type.EnumField = undefined;
    for (struct_fields, 0..) |field, i| {
        enum_fields[i] = .{ .name = field.name, .value = i };
    }
    return @Type(.{ .@"enum" = .{
        .decls = &.{},
        .tag_type = std.math.IntFittingRange(0, enum_fields.len - 1),
        .fields = &enum_fields,
        .is_exhaustive = true,
    } });
}

test FieldEnum {
    const Struct = struct {
        a: f32,
        b: u8,
        c: struct { z: u8, x: u8 },
    };

    const Enum1: FieldEnum(Struct) = .a;
    const Enum2: FieldEnum(Struct) = .b;
    const Enum3: FieldEnum(Struct) = .c;
    _ = Enum1;
    _ = Enum2;
    _ = Enum3;
}

pub fn FieldType(comptime Struct: type, comptime field: FieldEnum(Struct)) type {
    const s: Struct = undefined;
    return @TypeOf(@field(s, @tagName(field)));
}

test FieldType {
    const t = std.testing;

    const SubStruct = struct { x: f32, y: f32 };
    const Struct = struct { a: f32, b: u8, c: SubStruct };
    try t.expectEqual(f32, FieldType(Struct, .a));
    try t.expectEqual(u8, FieldType(Struct, .b));
    try t.expectEqual(SubStruct, FieldType(Struct, .c));
}
