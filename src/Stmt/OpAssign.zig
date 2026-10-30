const std = @import("std");

const okc = @import("okc");

left: okc.Expr,
kind: okc.Expr.Binary.Kind,
right: okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const vari = try self.left.genRef(ctx);
    const typ_val = try okc.Expr.Binary.gen(.{
        .left = self.left,
        .kind = self.kind,
        .right = self.right,
    }, ctx);
    try typ_val.store(vari.val, ctx);
}

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.ControlFlow {
    var left = try self.left.check(.{ .mutable = true }, ctx);
    if (!left.mutable) {
        ctx.failer.notMut(self.left.location);
    }
    std.debug.assert(self.kind.getClass() == .arith);
    if (!left.typ.isNumber()) {
        ctx.failer.wrongTyp(self.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try self.right.check(.{}, ctx);
    _ = right.typ.unify(left.typ, self.right.location, ctx.failer);
    return .cont;
}
