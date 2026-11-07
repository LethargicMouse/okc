const okc = @import("okc");
const std = @import("std");

expr: ?okc.Expr,

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const location = ctx.getLocation();
    try ctx.expect(.ret, .quiet);
    const expr = try ctx.maybe(okc.Expr.parse, .{.loud});
    try ctx.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .{ .ret = .{
            .expr = expr,
        } },
    };
}

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
    ctx: *okc.Stmt.Check,
) !okc.ControlFlow {
    std.log.debug("ret stmt, expect `{f}`", .{ctx.header.ret_typ});
    if (ret.expr) |*expr| {
        const info = try expr.check(.{ .typ = ctx.header.ret_typ }, ctx.exprCheckCtx());
        _ = info.typ.unify(ctx.header.ret_typ, expr.location, ctx.failer);
    } else if (!ctx.header.ret_typ.isVoid()) {
        ctx.failer.fail(location, "should return a value", .{});
    }
    return .ret;
}
