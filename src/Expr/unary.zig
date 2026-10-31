const okc = @import("okc");

pub const Unary = enum {
    deref,
    neg,
    notb,
    ptr,

    pub fn parseExpr(self: *okc.Parser) error{
        OutOfMemory,
        ParseFailed,
    }!okc.Expr {
        const start = self.getLocation();
        const unary: okc.Expr.Unary = try .parse(self);
        const expr = try self.parseExprPosted(.loud);
        return .{
            .location = start.combine(expr.location),
            .kind = try .makeUnary(unary, expr, self.arena),
        };
    }

    fn parse(ctx: *okc.Parser) !@This() {
        ctx.cursor += 1;
        return fromLexeme(ctx.tokens[ctx.cursor - 1].lexeme) orelse error.ParseFailed;
    }

    fn fromLexeme(lexeme: okc.Lexeme) ?@This() {
        return switch (lexeme) {
            .amp => .ptr,
            .star => .deref,
            .tild => .notb,
            .minus => .neg,
            else => null,
        };
    }
};
