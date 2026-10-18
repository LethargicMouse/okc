const okc = @import("okc");

mtyp: ?okc.Typ,
exprs: []okc.Expr,
typ: okc.Typ = .any,

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    try ctx.buffer.?.print(ctx.gpa, "{f} [", .{okc.Typ.LLPrinter{ .typ = self.typ }});
    if (self.exprs.len != 0) {
        try ctx.buffer.?.print(ctx.gpa, "\n  ", .{});
        _ = try self.exprs[0].genConst(ctx);
        for (self.exprs[1..]) |expr| {
            try ctx.buffer.?.print(ctx.gpa, ",\n  ", .{});
            _ = try expr.genConst(ctx);
        }
    }
    try ctx.buffer.?.print(ctx.gpa, "\n]", .{});
    return self.typ;
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    var inner_typ: okc.Typ = .any;
    var inner_hint: okc.Typ = .any;
    if (self.mtyp) |typ| {
        inner_typ = typ;
        inner_hint = typ;
    } else if (hint == .array) {
        inner_hint = hint.array.typ.*;
    }
    if (self.exprs.len == 0) {
        const typ = okc.Typ{ .array = .{
            .typ = try okc.Typ.memo.box(inner_hint, ctx.arena),
            .len = 0,
        } };
        return .{
            .typ = typ,
            .mutable = false,
        };
    }
    for (self.exprs) |*expr| {
        const info = try expr.check(.{ .typ = inner_hint }, ctx);
        inner_typ = info.typ.unify(inner_typ, expr.location, ctx.failer);
    }
    self.typ = okc.Typ{ .array = .{
        .typ = try okc.Typ.memo.box(inner_typ, ctx.arena),
        .len = self.exprs.len,
    } };
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
