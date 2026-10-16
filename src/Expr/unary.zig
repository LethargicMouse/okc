const okc = @import("okc");

pub const Unary = enum {
    deref,
    neg,
    notb,
    ptr,

    pub fn fromLexeme(lexeme: okc.Lexeme) ?@This() {
        return switch (lexeme) {
            .amp => .ptr,
            .star => .deref,
            .tild => .notb,
            .minus => .neg,
            else => null,
        };
    }
};
