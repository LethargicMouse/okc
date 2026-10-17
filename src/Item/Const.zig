const okc = @import("okc");

declare: okc.Stmt.Declare,

pub fn reg(self: *@This(), ctx: okc.Item.Check) !okc.Stmt.Declare.Info {
    const hint_typ = if (self.declare.typ) |typ| typ else .any;
    const typ = try self.declare.expr.checkConst(.{ .typ = hint_typ }, ctx.checkExprCtx());
    if (self.declare.typ) |typ_decl| {
        _ = typ_decl.unify(typ, self.declare.expr.location, ctx.failer);
    }
    return .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    };
}
