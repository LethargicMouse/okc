const okc = @import("okc");

branch: okc.Stmt.Branch,

pub fn check(self: *@This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const control_flow = try self.branch.check(.loop, ctx);
    switch (control_flow) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}
