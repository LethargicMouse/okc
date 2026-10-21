const okc = @import("okc");

vari: okc.Expr.Var,
typ: okc.Typ = .any,

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    try ctx.expect(.dot, .quiet);
    const location = ctx.getLocation();
    const vari: okc.Expr.Var = try .parse(ctx, .quiet);
    return .{
        .location = location,
        .kind = .{ .member = .{ .vari = vari } },
    };
}
