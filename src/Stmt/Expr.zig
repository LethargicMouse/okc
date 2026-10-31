const okc = @import("okc");

expr: okc.Expr,

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try self.expr.check(.{}, ctx);
    _ = info.typ.unify(.{ .prime = .void }, self.expr.location, ctx.failer);
    return .cont;
}

pub const Postfix = union(enum) {
    assign: okc.Expr,
    op_assign: okc.Stmt.OpAssign.Postfix,
    none,
};
