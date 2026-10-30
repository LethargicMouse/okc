const std = @import("std");

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

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const left = try self.left.gen(ctx);
    const right = try self.right.gen(ctx);
    const tmp = try okc.Expr.Binary.genOnVals(self.kind, left.typ, left.bare, right.bare, ctx);
    return .{
        .typ = self.kind.getRetTyp(left.typ),
        .bare = .{ .tmp = tmp },
    };
}

pub fn genOnVals(kind: Kind, typ: okc.Typ, a: okc.Val, b: okc.Val, ctx: *okc.Codegen) !u32 {
    const tmp = ctx.counter.next();
    try ctx.buffer.?.print(
        ctx.gpa,
        "\n  %t{} = {f} {f} {f}, {f}",
        .{ tmp, kind, okc.Typ.LLPrinter{ .typ = typ }, a, b },
    );
    return tmp;
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

    pub fn getRetTyp(self: @This(), child_typ: okc.Typ) okc.Typ {
        return switch (self.getClass()) {
            .arith => child_typ,
            .bool => .{ .prime = .bool },
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        const str = switch (self) {
            .moreq => "icmp sge",
            .orb => "or",
            .andb => "and",
            .add => "add",
            .sub => "sub",
            .mul => "mul",
            .div => "sdiv",
            .rem => "srem",
            .equ => "icmp eq",
            .les => "icmp slt",
            .neq => "icmp ne",
        };
        try writer.writeAll(str);
    }

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
};

pub const Class = enum {
    arith,
    bool,
};
