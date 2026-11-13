const okc = @import("okc");

stmts: []okc.Stmt,

pub const empty = @This(){ .stmts = @constCast(&.{}) };

pub fn parse(ctx: *okc.Parser) error{ OutOfMemory, ParseFailed }!okc.Stmt.Block {
    try ctx.expect(.curl, .loud);
    const stmts = try ctx.many(okc.Stmt.parse, .{});
    try ctx.expect(.curr, .quiet);
    return .{ .stmts = stmts };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    for (self.stmts) |stmt| {
        try stmt.gen(ctx);
    }
}

pub fn checkLoop(self: @This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    ctx.loops_nested += 1;
    const res = try self.check(ctx);
    ctx.loops_nested -= 1;
    switch (res) {
        .brek, .cont => return .cont,
        else => return res,
    }
}

pub fn check(self: @This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    var res: okc.ControlFlow = .cont;
    const rbp = ctx.vars_stack.items.len;
    defer ctx.freeVars(rbp);
    for (self.stmts, 0..) |*stmt, i| {
        const control_flow = try stmt.check(ctx);
        if (control_flow != .cont) {
            if (res == .cont) {
                res = control_flow;
            }
            if (i + 1 != self.stmts.len) {
                ctx.failer.fail(self.stmts[i + 1].location, "statement is unreachable", .{});
            }
        }
    }
    return res;
}
