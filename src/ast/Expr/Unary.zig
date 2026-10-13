const Expr = @import("Expr.zig");
const Lexeme = @import("../../Lexer.zig").Lexeme;

kind: Kind,
expr: Expr,

pub const Kind = enum {
    deref,
    neg,
    notb,
    ptr,

    pub fn fromLexeme(lexeme: Lexeme) ?Kind {
        return switch (lexeme) {
            .amp => .ptr,
            .star => .deref,
            .tild => .notb,
            .minus => .neg,
            else => null,
        };
    }
};
