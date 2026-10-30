const std = @import("std");

const okc = @import("okc");

bare: []const u8,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const info = try ctx.genStrDecl(self.bare);
    const ptr_u8 = try okc.Typ.memo.box(.{ .prime = .u8 }, ctx.arena);
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = ptr_u8,
            .sized = true,
            .mutable = false,
        } },
        .bare = .undef,
    };
    try res.genIV(.{
        .typ = .{ .ptr = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .bare = .{ .str = info.tmp },
    }, 0, ctx);
    try res.genIV(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = info.len },
    }, 1, ctx);
    return res;
}

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
