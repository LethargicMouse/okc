const okc = @import("okc");

condition: okc.Expr,
body: okc.Stmt.Block,

pub fn gen(self: @This(), end_label: u32, kind: Kind, ctx: *okc.Codegen) !void {
    const condition = try self.condition.gen(ctx);
    const then_label = ctx.counter.next();
    const else_label = ctx.counter.next();
    if (kind == .loop) {
        try ctx.loop_ends.append(ctx.gpa, else_label);
    }
    try ctx.cond(condition.bare, then_label, else_label);
    try self.body.gen(ctx);
    try ctx.uncond(end_label, else_label);
    if (kind == .loop) {
        _ = ctx.loop_ends.pop();
    }
}

pub fn check(
    self: *@This(),
    kind: Kind,
    ctx: *okc.Stmt.Check,
) !okc.ControlFlow {
    const info = try self.condition.check(.{}, ctx.exprCheckCtx());
    _ = info.typ.unify(.{ .prime = .bool }, self.condition.location, ctx.failer);
    if (kind == .loop) {
        return self.body.checkLoop(ctx);
    } else {
        return self.body.check(ctx);
    }
}

pub const Kind = enum {
    loop,
    simple,
};
