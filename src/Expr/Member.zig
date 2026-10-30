const okc = @import("okc");

vari: okc.Expr.Var,
typ: okc.Typ.Name = .{ .name = "<unknown>" },

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx);
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    return self.vari.genRefIn(self.typ, ctx);
}

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint: okc.Typ,
    mutability: okc.Expr.Var.Mutability,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    if (hint.getName()) |typ| {
        self.typ = typ;
        return self.vari.checkIn(typ, location, mutability, ctx);
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
