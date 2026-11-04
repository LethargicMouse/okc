const okc = @import("okc");

expr: okc.Expr,
vari: okc.Expr.Var,
args: []okc.Expr,
context: okc.Expr.Call.Context,
name_location: okc.Location,
caller: okc.Typ.Name = .{ .name = "<unknown>" },

pub fn parsePostfix(ctx: *okc.Parser) !okc.Expr.Postfix {
    try ctx.expect(.dot, .quiet);
    const location = ctx.getLocation();
    const name = try ctx.parseName(.quiet);
    const call: okc.Expr.Call.Postfix = try .parse(ctx);
    return .{
        .location = ctx.tmp_location,
        .kind = .{ .method = .{
            .vari = .{ .name = name },
            .args = call.args,
            .context = call.context,
            .name_location = location,
        } },
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const old = ctx.module;
    ctx.module = try .get(self.caller.name, ctx);
    const callee = try self.vari.kind.fun.gen(self.vari.name, ctx);
    ctx.module = old;
    const first = if (self.args.len != callee.typ.fun.params.len)
        try self.expr.gen(ctx)
    else
        null;
    return okc.Expr.Call.genWithVal(callee, first, self.args, self.context, ctx);
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    var caller = try self.expr.check(.{}, ctx);
    if (caller.typ == .err) {
        for (self.args) |*expr| {
            _ = try expr.check(.{}, ctx);
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    }
    var first: ?okc.Expr.Info.Located = null;
    if (caller.typ == .typ) {
        caller.typ = .{ .name = .{ .name = self.expr.kind.vari.name } };
    } else {
        first = .{
            .bare = caller,
            .location = self.expr.location,
        };
    }
    const callee = try self.vari.checkIn(caller.typ, self.name_location, .constant, ctx);
    self.caller = caller.typ.getName().?;
    const info_call: okc.Expr.Call.Info = .{
        .location = self.name_location,
        .typ = callee.typ,
        .args = self.args,
        .context = self.context,
        .maybe_first = first,
    };
    return info_call.check(hint, ctx);
}

pub const Postfix = struct {
    vari: okc.Expr.Var,
    args: []okc.Expr,
    context: okc.Expr.Call.Context,
    name_location: okc.Location,
};
