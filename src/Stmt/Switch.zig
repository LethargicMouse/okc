const okc = @import("okc");

expr: okc.Expr,
branches: []const Branch,

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
        try ctx.expect(.arrow, .loud);
        const body = try ctx.parseBlock();
        return .{
            .variants = variants,
            .body = body,
        };
    }
};
