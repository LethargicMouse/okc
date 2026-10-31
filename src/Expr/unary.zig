const okc = @import("okc");

pub const Unary = enum {
    deref,
    neg,
    notb,
    ptr,

    pub fn parse(ctx: *okc.Parser) !@This() {
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
