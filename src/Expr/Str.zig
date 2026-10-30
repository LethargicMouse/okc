const std = @import("std");

const okc = @import("okc");

bare: []const u8,

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    const info = try ctx.genStrDecl(self.bare);
    try ctx.buffer.?.print(
        ctx.gpa,
        "%\"[]\" {{ ptr @.s{d}, i64 {d} }}",
        .{ info.tmp, info.len },
    );
    return .{ .slice = .{
        .typ = try okc.Typ.memo.box(.{ .prime = .u8 }, ctx.arena),
        .sized = true,
        .mutable = false,
    } };
}

pub fn check(arena: std.mem.Allocator) !okc.Expr.Info {
    const ptr = try okc.Typ.memo.box(.{ .prime = .u8 }, arena);
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .sized = true,
            .mutable = false,
        } },
        .mutable = false,
    };
}

pub const GenInfo = struct {
    len: usize,
    tmp: u32,
};

pub const Unescaped = struct {
    len: usize,
    repr: []const u8,
};
