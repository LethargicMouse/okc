const Expr = @import("mod.zig");
const Lexeme = @import("../../Lexer.zig").Lexeme;

const Self = @This();
kind: Kind,
expr: Expr,

pub const Kind = enum {
    ptr,
    deref,
    notb,
    neg,

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
