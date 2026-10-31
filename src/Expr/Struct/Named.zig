const okc = @import("okc");

bare: okc.Expr.Struct,
name: []const u8,

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    const location = ctx.getLocation();
    const name = try ctx.parseName(.quiet);
    const fields = try okc.Expr.Struct.parseBody(ctx);
    return .{
        .location = location,
        .kind = .{ .named_struc = .{
            .name = name,
            .bare = .{ .fields = fields },
        } },
    };
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    return self.bare.typed(.{ .name = self.name }).check(location, ctx);
}
