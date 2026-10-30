const okc = @import("okc");

expr: okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const val = try self.expr.gen(ctx);
    const tmp = ctx.counter.next();
    try ctx.buffer.?.print(
        ctx.gpa,
        "\n  %t{d} = sub {f} 0, {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = val.typ }, val.bare },
    );
    return .{
        .typ = val.typ,
        .bare = .{ .tmp = tmp },
    };
}

pub fn check(self: *@This(), ctx: okc.Expr.Check) !okc.Expr.Info {
    var info = try self.expr.check(.{}, ctx);
    if (!info.typ.isNumber()) {
        ctx.failer.wrongTyp(self.expr.location, .int, info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}
