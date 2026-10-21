const okc = @import("okc");

vari: []const u8,
expr: okc.Expr,
body: okc.Stmt.Block,
vari_location: okc.Location,

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const info = try self.expr.check(.{}, ctx.exprCheckCtx());
    const elem_info = info.getElem(self.expr.location, ctx.failer) orelse okc.Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    try ctx.declare(self.vari, self.vari_location, .{
        .typ = elem_info.typ,
        .mutable = false,
        .can_be_mutable = false,
    }, ctx.failer);
    defer {
        _ = ctx.vars_stack.pop();
        ctx.freeVar(self.vari);
    }
    return self.body.checkLoop(ctx);
}
