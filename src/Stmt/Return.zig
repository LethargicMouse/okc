const okc = @import("okc");

expr: ?okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    if (self.expr) |expr| {
        const val = try expr.gen(ctx);
        try ctx.buffer.print(ctx.gpa, "\n  ret {f}", .{val});
    } else {
        try ctx.buffer.print(ctx.gpa, "\n  ret void", .{});
    }
}

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
