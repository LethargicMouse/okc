const okc = @import("okc");

vari: okc.Expr.Var,
typ: okc.Typ = .any,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx);
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    return self.vari.genRefIn(self.typ.name, ctx);
}

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint: okc.Typ,
    mutability: okc.Expr.Var.Mutability,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    if (hint == .any) {
        ctx.failer.cannotInfer(.any, location);
        return .{ .typ = .err, .mutable = true };
    }
    self.typ = hint;
    return self.vari.checkIn(hint, location, mutability, ctx);
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
