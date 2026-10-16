const okc = @import("okc");

declare: okc.Stmt.Declare,

pub fn reg(self: *@This(), ctx: okc.Item.Check) !okc.Item.Info.Kind {
    const hint_typ = if (self.declare.typ) |typ| typ else .any;
    const typ = try self.declare.expr.checkConst(.{ .typ = hint_typ }, ctx.checkExpr());
    if (self.declare.typ) |typ_decl| {
        _ = typ_decl.unify(typ, self.declare.expr.location, ctx.failer);
    }
    return .{ .vari = .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    } };
}
