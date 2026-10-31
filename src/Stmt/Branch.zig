const okc = @import("okc");

condition: okc.Expr,
body: okc.Stmt.Block,

pub fn cond(
    condition: okc.Val,
    then_label: u32,
    else_label: u32,
    ctx: *okc.Codegen,
) !void {
    try ctx.buffer.print(ctx.gpa,
        \\
        \\  br i1 {f}, label %l{}, label %l{}
        \\l{}:
    , .{
        condition,
        then_label,
        else_label,
        then_label,
    });
}

pub fn uncond(to: u32, next: u32, ctx: *okc.Codegen) !void {
    try ctx.buffer.print(ctx.gpa,
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
}

pub fn gen(self: @This(), end_label: u32, kind: Kind, ctx: *okc.Codegen) !void {
    const condition = try self.condition.gen(ctx);
    const then_label = ctx.counter.next();
    const else_label = ctx.counter.next();
    if (kind == .loop) {
        try ctx.loop_ends.append(ctx.gpa, else_label);
    }
    try cond(condition.bare, then_label, else_label, ctx);
    try self.body.gen(ctx);
    try uncond(end_label, else_label, ctx);
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
