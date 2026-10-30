const okc = @import("okc");

left: okc.Expr,
expr: okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const vari = try self.left.genRef(ctx);
    const typ_val = try self.expr.gen(ctx);
    try typ_val.store(vari.val, ctx);
}

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.ControlFlow {
    const left = try self.left.check(.{ .mutable = true }, ctx);
    if (!left.mutable) {
        ctx.failer.notMut(self.left.location);
    }
    const info = try self.expr.check(.{ .typ = left.typ }, ctx);
    _ = info.typ.unify(left.typ, self.expr.location, ctx.failer);
    return .cont;
}
