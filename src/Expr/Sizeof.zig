const okc = @import("okc");

typ: okc.Typ,

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    const start = ctx.getLocation();
    try ctx.expect(.sizeof, .quiet);
    try ctx.expect(.les, .loud);
    const typ: okc.Typ = try .parse(ctx);
    const end = ctx.getLocation();
    try ctx.expect(.mor, .loud);
    return .{
        .location = start.combine(end),
        .kind = .{ .sizeof = .{ .typ = typ } },
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const resolved = try self.typ.resolve(.{
        .gpa = ctx.gpa,
        .arena = ctx.arena,
        .map = ctx.resolve_map,
    });
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
