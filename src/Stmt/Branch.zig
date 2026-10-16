const okc = @import("okc");

condition: okc.Expr,
body: okc.Stmt.Block,

pub fn check(
    self: *@This(),
    kind: Kind,
    ctx: *okc.Stmt.Check,
) !okc.ControlFlow {
    const info = try self.condition.check(.{}, ctx.exprCheck());
    const expected: okc.Typ = .{ .prime = .bool };
    _ = expected.unify(info.typ, self.condition.location, ctx.failer);
    if (kind == .loop) {
        return self.body.checkLoop(ctx);
    } else {
        return self.body.check(ctx);
    }
}

pub const Kind = enum {
    loop,
    simple,
};
