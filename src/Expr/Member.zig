const okc = @import("okc");

vari: okc.Expr.Var,
typ: okc.Typ = .any,

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint: okc.Typ,
    mutability: okc.Expr.Var.Mutability,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    if (hint.getName()) |name| {
        return self.vari.checkIn(name, location, mutability, ctx);
    }
    ctx.failer.cannotInfer(hint, location);
    return .{ .typ = .err, .mutable = true };
}

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    try ctx.expect(.dot, .quiet);
    const location = ctx.getLocation();
    const vari: okc.Expr.Var = try .parse(ctx, .quiet);
    return .{
        .location = location,
        .kind = .{ .member = .{ .vari = vari } },
    };
}
