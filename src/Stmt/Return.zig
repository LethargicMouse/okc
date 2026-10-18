const okc = @import("okc");

expr: ?okc.Expr,

pub fn check(
    ret: *@This(),
    location: okc.Location,
    ret_typ: okc.Typ,
    ctx: okc.Expr.Check,
) !okc.ControlFlow {
    if (ret.expr) |*expr| {
        const info = try expr.check(.{ .typ = ret_typ }, ctx);
        _ = info.typ.unify(ret_typ, expr.location, ctx.failer);
    } else if (!ret_typ.isVoid()) {
        ctx.failer.fail(location, "should return a value", .{});
    }
    return .ret;
}
