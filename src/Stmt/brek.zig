const okc = @import("okc");

pub fn check(location: okc.Location, ctx: okc.Stmt.Check) error{OutOfMemory}!okc.ControlFlow {
    if (ctx.loops_nested == 0) {
        ctx.failer.fail(location, "`break` outside of loop", .{});
        return .cont;
    }
    return .brek;
}
