const okc = @import("okc");

branch: okc.Stmt.Branch,

pub fn gen(self: @This(), ctx: *okc.Codegen) !void {
    const condition_label = ctx.counter.next();
    try okc.Stmt.Branch.uncond(condition_label, condition_label, ctx);
    try self.branch.gen(condition_label, .loop, ctx);
}

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const control_flow = try self.branch.check(.loop, ctx);
    switch (control_flow) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}
