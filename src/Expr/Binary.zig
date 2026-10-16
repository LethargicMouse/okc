const Checker = @import("../Checker.zig");
const Expr = @import("Expr.zig");
const fail = @import("../fail.zig");
const Lexeme = @import("../Lexer.zig").Lexeme;
const Typ = @import("../typ/typ.zig").Typ;

left: Expr,
kind: Kind,
right: Expr,

pub fn check(self: *@This(), checker: *Checker) !Expr.Info {
    var left = try checker.checkExpr(&self.left, .{});
    if (!left.typ.isNumber()) {
        fail.wrongTyp(self.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try checker.checkExpr(&self.right, .{});
    const unityp = Checker.unify(self.right.location, left.typ, right.typ);
    const typ = switch (self.kind.getClass()) {
        .arith => unityp,
        .bool => Typ{ .prime = .bool },
    };
    return .{
        .typ = typ,
        .mutable = false,
    };
}

pub const Kind = enum {
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

    pub const Class = enum {
        arith,
        bool,
    };
};
