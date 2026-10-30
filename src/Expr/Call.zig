const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,
context: Context,

pub const Context = @import("Call/Context.zig");
pub const Postfix = @import("Call/Postfix.zig");

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const callee = try self.expr.check(.{}, ctx);
    const info_call: okc.Expr.Info.Call = .{
        .args = self.args,
        .location = self.expr.location,
        .maybe_first = null,
        .typ = callee.typ,
    };
    return info_call.check(hint, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const callee = try self.expr.gen(ctx);
    return callee.genCall(null, self.args, ctx);
}
