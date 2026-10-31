const okc = @import("okc");

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const location = ctx.getLocation();
    try ctx.expect(.unre, .quiet);
    try ctx.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .unre,
    };
}

pub fn gen(ctx: *okc.Codegen) !void {
    try ctx.buffer.appendSlice(ctx.gpa, "\n  unreachable");
}
