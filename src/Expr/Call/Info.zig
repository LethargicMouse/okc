const okc = @import("okc");

typ: okc.Typ,
args: []okc.Expr,
context: okc.Expr.Call.Context,
maybe_first: ?okc.Expr.Info.Located,
location: okc.Location,

pub fn check(self: @This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const fun = self.typ.getFun(self.location, ctx.failer) orelse {
        for (self.args) |*arg| {
            _ = try arg.check(.{}, ctx);
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    };
    // to propagate hint to generics
    _ = fun.ret_typ.unifyOrNull(hint, .active);
    var params = fun.params;
    if (self.maybe_first) |first| {
        params = fun.params[1..];
        _ = first.bare.typ.unify(fun.params[0], self.location, ctx.failer);
    }
    for (self.args, params) |*arg, param| {
        const info = try arg.check(.{ .typ = param }, ctx);
        _ = info.typ.unify(param, arg.location, ctx.failer);
    }
    for (self.context.fields) |*field| {
        _ = try field.expr.check(.{}, ctx);
    }
    return .{
        .typ = fun.ret_typ.*,
        .mutable = false,
    };
}
