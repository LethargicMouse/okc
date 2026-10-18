const okc = @import("okc");

vari: []const u8,
start: okc.Expr,
end: okc.Expr,
body: okc.Stmt.Block,
vari_location: okc.Location,

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    var start = try self.start.check(.{}, ctx.exprCheck());
    if (!start.typ.isNumber()) {
        ctx.failer.wrongTyp(self.start.location, .int, start.typ);
        start.typ = .err;
    }
    const end = try self.end.check(.{}, ctx.exprCheck());
    const typ = end.typ.unify(start.typ, self.end.location, ctx.failer);
    try ctx.declare(self.vari, self.vari_location, .{
        .typ = typ,
        .mutable = false,
        .can_be_mutable = false,
    }, ctx.failer);
    defer {
        _ = ctx.vars_stack.pop();
        ctx.freeVar(self.vari);
    }
    return self.body.checkLoop(ctx);
}
