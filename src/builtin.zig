const Location = @import("Location.zig");
const Pos = @import("Pos.zig");
const Ast = @import("Ast.zig");

pub const str_struct = Ast.Struct{
    .name = "str",
    .fields = &.{
        .{
            .name = "ptr",
            .typ = .{ .ptr = u8_ptr },
            .location = loc(pos(2, 3), pos(2, 6)),
        },
        .{
            .name = "len",
            .typ = .{ .prime = .u64 },
            .location = loc(pos(3, 3), pos(3, 6)),
        },
    },
    .location = loc(pos(1, 8), pos(1, 11)),
};

const u8_ptr = &Ast.Typ{ .prime = .u8 };

const lines = &.{
    "struct str {",
    "  ptr: &u8,",
    "  len: u64,",
    "}",
};

fn loc(start: Pos, end: Pos) Location {
    return .{
        .lines = lines,
        .name = "<builtin>",
        .start = start,
        .end = end,
    };
}

fn pos(line: u32, symbol: u32) Pos {
    return .{ .line = line, .symbol = symbol };
}
