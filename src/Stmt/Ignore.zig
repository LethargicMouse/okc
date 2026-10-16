const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.ControlFlow {
    const info = try self.expr.check(.{}, ctx);
    if (info.typ.isVoid()) {
        ctx.failer.fail(location, "redundant ignore", .{});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}
