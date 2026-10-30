const okc = @import("okc");

typ: okc.Typ,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const resolved = try self.typ.resolve(ctx.resolve_map, ctx.arena);
    const layout = try resolved.getLayout(ctx);
    return .{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = layout.size },
    };
}

pub fn check(self: *@This()) !okc.Expr.Info {
    _ = self;
    return .{
        .typ = .{ .prime = .u64 },
        .mutable = false,
    };
}
