const Expr = @import("Expr.zig");
const Lexeme = @import("../../Lexer.zig").Lexeme;

left: Expr,
kind: Kind,
right: Expr,

pub const Kind = enum {
    pub const Class = enum {
        arith,
        bool,
    };
    add,
    andb,
    div,
    equ,
    les,
    moreq,
    mul,
    neq,

    orb,
    rem,
    sub,

    pub fn getPrior(kind: Kind) u8 {
        switch (kind) {
            .equ, .neq, .les, .moreq => return 0,
            .orb => return 1,
            .andb => return 2,
            .add, .sub => return 3,
            .mul, .div, .rem => return 4,
        }
    }

    pub fn fromLexeme(lexeme: Lexeme) ?Kind {
        return switch (lexeme) {
            .pipe => .orb,
            .amp => .andb,
            .equ2 => .equ,
            .plus => .add,
            .minus => .sub,
            .star => .mul,
            .slash => .div,
            .les => .les,
            .rem => .rem,
            .moreq => .moreq,
            else => null,
        };
    }

    pub fn getClass(kind: Kind) Class {
        return switch (kind) {
            .orb, .andb, .add, .sub, .mul, .div, .rem => .arith,
            .equ, .neq, .les, .moreq => .bool,
        };
    }
};
