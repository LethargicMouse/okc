const okc = @import("okc");

branch: okc.Stmt.Branch,
else_ifs: []okc.Stmt.Branch,
else_block: okc.Stmt.Block,

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
