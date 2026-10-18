const okc = @import("okc");

left: okc.Expr,
kind: Kind,
right: okc.Expr,

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.Expr.Info {
    var left = try self.left.check(.{}, ctx);
    if (!left.typ.isNumber()) {
        ctx.failer.wrongTyp(self.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try self.right.check(.{}, ctx);
    const unityp = right.typ.unify(left.typ, self.right.location, ctx.failer);
    const typ = switch (self.kind.getClass()) {
        .arith => unityp,
        .bool => okc.Typ{ .prime = .bool },
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

    pub fn fromLexeme(lexeme: okc.Lexeme) ?Kind {
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
