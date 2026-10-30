const okc = @import("okc");

expr: okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.expr.genRef(ctx);
    return ref.toPtrTypVal(ctx.arena);
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const mutable = if (hint == .ptr) hint.ptr.mutable else false;
    const info = try self.expr.check(.{ .mutable = mutable }, ctx);
    const ptr = try okc.Typ.memo.box(info.typ, ctx.arena);
    return .{
        .typ = .{ .ptr = .{
            .typ = ptr,
            .mutable = info.mutable,
        } },
        .mutable = false,
    };
}
