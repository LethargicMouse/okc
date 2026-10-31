const okc = @import("okc");

vari: []const u8,
expr: okc.Expr,
body: okc.Stmt.Block,
vari_location: okc.Location,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const slice = try self.expr.genRef(ctx);
    // int i = 0
    const iref = try okc.Val.Typed.toStack(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = 0 },
    }, ctx);
    // goto cond
    // start:
    const start_label = ctx.counter.next();
    const cond_label = ctx.counter.next();
    try okc.Stmt.Branch.uncond(cond_label, start_label, ctx);
    // i++
    const ival = try iref.loadTypVal(ctx);
    const inew = try okc.Expr.Binary.genOnVals(.add, ival.typ, ival.bare, .{ .int = 1 }, ctx);
    try okc.Val.Typed.store(.{ .typ = ival.typ, .bare = .{ .tmp = inew } }, iref.val, ctx);
    // goto cond
    // cond:
    try okc.Stmt.Branch.uncond(cond_label, cond_label, ctx);
    // cond = i < .len
    const ival_ = try iref.loadTypVal(ctx);
    const len_field: okc.Expr.Field = .{
        .expr = self.expr,
        .vari = .{ .name = "len" },
    };
    const len = try len_field.gen(ctx);
    const less = try okc.Expr.Binary.genOnVals(.les, ival.typ, ival_.bare, len.bare, ctx);
    // if cond, body, end
    // body:
    const body_label = ctx.counter.next();
    const end_label = ctx.counter.next();
    try okc.Stmt.Branch.cond(.{ .tmp = less }, body_label, end_label, ctx);
    // var = slice[i]
    const elem = try slice.genElem(ival_, ctx);
    try ctx.vars.put(self.vari, elem);
    // <body>
    try self.body.gen(ctx);
    // goto start
    // end:
    try okc.Stmt.Branch.uncond(start_label, end_label, ctx);
}

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const info = try self.expr.check(.{}, ctx.exprCheckCtx());
    const elem_info = info.getElem(self.expr.location, ctx.failer) orelse okc.Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    try ctx.declare(self.vari, self.vari_location, .{
        .typ = elem_info.typ,
        .mutable = false,
        .can_be_mutable = false,
    }, ctx.failer);
    defer {
        _ = ctx.vars_stack.pop();
        ctx.freeVar(self.vari);
    }
    return self.body.checkLoop(ctx);
}
