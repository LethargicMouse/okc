const okc = @import("okc");

expr: okc.Expr,
vari: okc.Expr.Var,
args: []okc.Expr,
name_location: okc.Location,
caller: okc.Typ.Name = .{ .name = "<unknown>" },

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const old = ctx.module;
    ctx.module = try ctx.getModule(self.caller.name);
    const callee = try ctx.genFunPtr(self.vari.name, self.vari.kind.fun);
    ctx.module = old;
    const first = if (self.args.len != callee.typ.fun.params.len)
        try self.expr.gen(ctx)
    else
        null;
    return callee.genCall(first, self.args, ctx);
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
    const inner_ctx = ctx.inside(caller.typ) orelse {
        ctx.failer.noMember(self.name_location, self.vari.name, caller.typ);
        for (self.args) |*expr| {
            _ = try expr.check(.{}, ctx);
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    };
    const callee = try self.vari.check(self.name_location, .constant, inner_ctx);
    self.caller = caller.typ.getName().?;
    const info_call: okc.Expr.Info.Call = .{
        .location = self.name_location,
        .typ = callee.typ,
        .args = self.args,
        .maybe_first = first,
    };
    return info_call.check(hint, ctx);
}
