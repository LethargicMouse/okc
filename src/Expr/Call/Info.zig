const std = @import("std");

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
    var defined: std.StringHashMap(okc.Location) = .init(ctx.gpa);
    defer defined.deinit();
    for (self.context.fields) |*field| {
        for (fun.context) |param| {
            if (std.mem.eql(u8, field.name, param.name)) {
                const info = try field.expr.check(.{ .typ = param.typ }, ctx);
                _ = info.typ.unify(param.typ, field.expr.location, ctx.failer);
                if (defined.get(param.name)) |prev| {
                    ctx.failer.alreadyDeclared(field.location, param.name, prev);
                } else {
                    try defined.put(param.name, field.location);
                }
                break;
            }
        } else {
            _ = try field.expr.check(.{}, ctx);
            ctx.failer.fail(field.location, "unused context", .{});
        }
    }
    for (fun.context) |param| {
        if (!defined.contains(param.name)) {
            ctx.failer.notInit(self.location, param.name, "ctx");
        }
    }
    return .{
        .typ = fun.ret_typ.*,
        .mutable = false,
    };
}
