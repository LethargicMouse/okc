const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const location = ctx.getLocation();
    try ctx.expect(.wild, .quiet);
    try ctx.expect(.equ, .loud);
    const expr: okc.Expr = try .parse(ctx, .loud);
    try ctx.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .{ .ignore = .{
            .expr = expr,
        } },
    };
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.ControlFlow {
    const info = try self.expr.check(.{}, ctx);
    if (info.typ.isVoid()) {
        ctx.failer.fail(location, "redundant ignore", .{});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}
