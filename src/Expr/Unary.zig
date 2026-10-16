const Expr = @import("Expr.zig");
const Lexeme = @import("../Lexer.zig").Lexeme;
const Location = @import("../Location.zig");
const Typ = @import("../typ/typ.zig").Typ;

kind: Kind,
expr: Expr,

pub fn check(unary: *Expr.Unary, location: Location, hint: Typ, ctx: Expr.Check) !Expr.Info {
    switch (unary.kind) {
        .deref => return Expr.Deref.check(&unary.expr, location, ctx),
        .notb => return Expr.Notb.check(&unary.expr, ctx),
        .ptr => return Expr.Ptr.check(&unary.expr, hint, ctx),
        .neg => return Expr.Neg.check(&unary.expr, ctx),
    }
}

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
