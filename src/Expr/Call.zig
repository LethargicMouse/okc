const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const callee_info = try self.expr.check(.{}, ctx);
    const fun = callee_info.typ.getFun(self.expr.location, ctx.failer) orelse
        return self.checkBad(ctx);
    // to propagate hint to generics
    _ = fun.ret_typ.unifyOrNull(hint, .active);
    for (self.args, fun.params) |*arg, param| {
        const info = try arg.check(.{ .typ = param.normalise() }, ctx);
        _ = param.unify(info.typ, arg.location, ctx.failer);
    }
    return .{
        .typ = fun.ret_typ.*,
        .mutable = false,
    };
}

fn checkBad(call: *@This(), ctx: okc.Expr.Check) !okc.Expr.Info {
    for (call.args) |*arg| {
        _ = try arg.check(.{}, ctx);
    }
    return .{
        .typ = .err,
        .mutable = false,
    };
}
