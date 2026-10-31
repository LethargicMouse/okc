const okc = @import("okc");

expr: okc.Expr,

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const expr: okc.Expr = try .parse(ctx, .quiet);
    const postfix: okc.Stmt.Expr.Postfix = try .parse(ctx);
    try ctx.expect(.semi, .loud);
    switch (postfix) {
        .none => return .{
            .location = expr.location,
            .kind = .{ .expr = .{ .expr = expr } },
        },
        .assign => |right| {
            return .{
                .location = expr.location.combine(right.location),
                .kind = .{ .assign = .{
                    .left = expr,
                    .expr = right,
                } },
            };
        },
        .op_assign => |op_assign| {
            const location = expr.location.combine(op_assign.expr.location);
            return .{
                .location = location,
                .kind = .{ .op_assign = .{
                    .left = expr,
                    .kind = op_assign.kind,
                    .right = op_assign.expr,
                } },
            };
        },
    }
}

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try self.expr.check(.{}, ctx);
    const typ = info.typ.unify(.{ .prime = .void }, self.expr.location, ctx.failer);
    if (typ == .never) {
        return .ret;
    }
    return .cont;
}

pub const Postfix = union(enum) {
    assign: okc.Expr,
    op_assign: okc.Stmt.OpAssign.Postfix,
    none,

    pub fn parse(ctx: *okc.Parser) !@This() {
        return ctx.either(.{
            okc.Stmt.Assign.parseStmtPostfix,
            okc.Stmt.OpAssign.parsePostfix,
        }) catch .none;
    }
};
