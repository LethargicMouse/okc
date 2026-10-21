const okc = @import("okc");

expr: okc.Expr,
branches: []const Branch,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const expr_ref = try self.expr.genRef(ctx);
    const tag = try expr_ref.loadTag(ctx.loadCtx());
    const swi_end_label = ctx.counter.next();
    try ctx.buffer.?.print(ctx.gpa, "\n  switch i32 %t{}, label %l{} [", .{ tag, swi_end_label });
    const labels = try ctx.gpa.alloc(u32, self.branches.len);
    defer ctx.gpa.free(labels);
    for (self.branches, labels) |branch, *label| {
        label.* = ctx.counter.next();
        for (branch.variants) |variant| {
            try ctx.buffer.?.appendSlice(ctx.gpa, "\n    ");
            _ = try variant.genConstField(0, ctx);
            try ctx.buffer.?.print(ctx.gpa, ", label %l{}", .{label.*});
        }
    }
    try ctx.buffer.?.print(ctx.gpa, "\n  ]\nl{}:", .{swi_end_label});
    const end_label = ctx.counter.next();
    for (self.branches, labels) |branch, label| {
        try ctx.uncond(end_label, label);
        try branch.body.gen(ctx);
    }
    try ctx.uncond(end_label, end_label);
}

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const expr = try self.expr.check(.{}, ctx.exprCheckCtx());
    var res: okc.ControlFlow = .ret;
    for (self.branches) |branch| {
        for (branch.variants) |*variant| {
            const info = try variant.check(.{ .typ = expr.typ }, ctx.exprCheckCtx());
            _ = info.typ.unify(expr.typ, variant.location, ctx.failer);
        }
        const control_flow = try branch.body.check(ctx);
        if (@backingInt(control_flow) < @backingInt(res)) {
            res = control_flow;
        }
    }
    return res;
}

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const location = ctx.getLocation();
    try ctx.expect(.swi, .quiet);
    try ctx.expect(.parl, .loud);
    const expr = try ctx.parseExpr(.loud);
    try ctx.expect(.parr, .loud);
    try ctx.expect(.curl, .loud);
    const branches = try ctx.many(Branch.parse, .{});
    try ctx.expect(.curr, .quiet);
    return .{
        .location = location,
        .kind = .{ .swi = .{
            .expr = expr,
            .branches = branches,
        } },
    };
}

pub const Branch = struct {
    variants: []okc.Expr,
    body: okc.Stmt.Block,

    fn parse(ctx: *okc.Parser) !@This() {
        const variants = try ctx.sep(okc.Parser.parseExpr, .{.loud});
        const body = try ctx.parseBlock();
        return .{
            .variants = variants,
            .body = body,
        };
    }
};
