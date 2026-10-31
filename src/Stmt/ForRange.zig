const okc = @import("okc");

vari: []const u8,
start: okc.Expr,
end: okc.Expr,
body: okc.Stmt.Block,
vari_location: okc.Location,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    // int i = start
    try okc.Stmt.Declare.Named.gen(.{
        .name = self.vari,
        .bare = .{
            .expr = self.start,
            .typ = null,
            .mutable = false,
        },
    }, ctx);
    const end = try self.end.gen(ctx);
    // goto cond
    // start:
    const start_label = ctx.counter.next();
    const cond_label = ctx.counter.next();
    try okc.Stmt.Branch.uncond(cond_label, start_label, ctx);
    // i++
    const ival = try ctx.vars.get(self.vari).?.loadTypVal(ctx);
    const inew = try okc.Expr.Binary.genOnVals(.add, ival.typ, ival.bare, .{ .int = 1 }, ctx);
    try okc.Val.Typed.store(
        .{ .typ = ival.typ, .bare = .{ .tmp = inew } },
        ctx.vars.get(self.vari).?.val,
        ctx,
    );
    // goto cond
    // cond:
    try okc.Stmt.Branch.uncond(cond_label, cond_label, ctx);
    // cond = i != end
    const ival_ = try ctx.vars.get(self.vari).?.loadTypVal(ctx);
    const at_end = try okc.Expr.Binary.genOnVals(.neq, ival.typ, ival_.bare, end.bare, ctx);
    // if cond, body, end
    // body:
    const body_label = ctx.counter.next();
    const end_label = ctx.counter.next();
    try okc.Stmt.Branch.cond(.{ .tmp = at_end }, body_label, end_label, ctx);
    // <body>
    try self.body.gen(ctx);
    // goto start
    // end:
    try okc.Stmt.Branch.uncond(start_label, end_label, ctx);
}

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    var start = try self.start.check(.{}, ctx.exprCheckCtx());
    if (!start.typ.isNumber()) {
        ctx.failer.wrongTyp(self.start.location, .int, start.typ);
        start.typ = .err;
    }
    const end = try self.end.check(.{}, ctx.exprCheckCtx());
    const typ = end.typ.unify(start.typ, self.end.location, ctx.failer);
    try ctx.declare(self.vari, self.vari_location, .{
        .typ = typ,
        .mutable = false,
        .can_be_mutable = false,
    }, ctx.failer);
    defer {
        _ = ctx.vars_stack.pop();
        ctx.freeVar(self.vari);
    }
    return self.body.checkLoop(ctx);
}
