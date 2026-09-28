const Expr = @import("../Expr.zig");
const Lexeme = @import("../../Lexer.zig").Lexeme;

const Unary = @This();
kind: Unary.Kind,
expr: Expr,

pub const Kind = enum {
    ptr,
    deref,
    notb,
    neg,

    pub fn fromLexeme(lexeme: Lexeme) ?Unary.Kind {
        return switch (lexeme) {
            .amp => .ptr,
            .star => .deref,
            .tild => .notb,
            .minus => .neg,
            else => null,
        };
    }
};
