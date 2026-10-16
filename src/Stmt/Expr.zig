const okc = @import("okc");

expr: okc.Expr,

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try self.expr.check(.{}, ctx);
    const expected: okc.Typ = .{ .prime = .void };
    _ = expected.unify(info.typ, self.expr.location, ctx.failer);
    return .cont;
}
