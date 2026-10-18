const okc = @import("okc");

expr: okc.Expr,
index: okc.Expr,

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    const info = try self.expr.check(.{}, ctx);
    const index = try self.index.check(.{}, ctx);
    _ = index.typ.unify(.{ .prime = .u64 }, self.index.location, ctx.failer);
    return info.getElem(location, ctx.failer) orelse .{
        .typ = .err,
        .mutable = true,
    };
}
