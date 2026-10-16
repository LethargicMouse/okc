const okc = @import("okc");

expr: okc.Expr,

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.Expr.Info {
    var info = try self.expr.check(.{}, ctx);
    if (!info.typ.isNumber()) {
        ctx.failer.wrongTyp(self.expr.location, .int, info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}
