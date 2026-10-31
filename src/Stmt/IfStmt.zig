const okc = @import("okc");

branch: okc.Stmt.Branch,
else_ifs: []okc.Stmt.Branch,
else_block: okc.Stmt.Block,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const end_label = ctx.counter.next();
    try self.branch.gen(end_label, .simple, ctx);
    for (self.else_ifs) |branch| {
        try branch.gen(end_label, .simple, ctx);
    }
    try self.else_block.gen(ctx);
    try okc.Stmt.Branch.uncond(end_label, end_label, ctx);
}

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    var res = try self.branch.check(.simple, ctx);
    for (self.else_ifs) |*branch| {
        const control_flow = try branch.check(.simple, ctx);
        if (@backingInt(control_flow) < @backingInt(res)) {
            res = control_flow;
        }
    }
    const control_flow = try self.else_block.check(ctx);
    if (@backingInt(control_flow) < @backingInt(res)) {
        res = control_flow;
    }
    return res;
}
