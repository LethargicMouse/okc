const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,
context: Context,

pub const Context = @import("Call/Context.zig");
pub const Info = @import("Call/Info.zig");
pub const Postfix = @import("Call/Postfix.zig");

pub fn parsePostfix(ctx: *okc.Parser) !okc.Expr.Postfix {
    const call: Postfix = try .parse(ctx);
    return .{
        .location = ctx.tmp_location,
        .kind = .{ .call = call },
    };
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const callee = try self.expr.check(.{}, ctx);
    const info: Info = .{
        .args = self.args,
        .context = self.context,
        .location = self.expr.location,
        .maybe_first = null,
        .typ = callee.typ,
    };
    return info.check(hint, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const callee = try self.expr.gen(ctx);
    return callee.genCall(null, self.args, ctx);
}
