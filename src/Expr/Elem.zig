const okc = @import("okc");

expr: okc.Expr,
index: okc.Expr,

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    const ref = try self.expr.genRef(ctx);
    var index_ref = try self.index.genRef(ctx);
    var index: okc.Val.Typed = undefined;
    if (index_ref.inner_typ.getName()) |_| {
        index = .{
            .typ = .{ .prime = .u32 },
            .bare = .{ .tmp = try index_ref.loadTag(ctx) },
        };
    } else {
        index = try index_ref.loadTypVal(ctx);
    }
    return ref.genElem(index, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx);
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    const info = try self.expr.check(.{}, ctx);
    const index = try self.index.check(.{}, ctx);
    const expected: okc.Typ = switch (info.typ.normalise()) {
        .array => |array| array.index.getTyp(),
        else => .{ .prime = .u64 },
    };
    _ = index.typ.unify(expected, self.index.location, ctx.failer);
    return info.getElem(location, ctx.failer) orelse .{
        .typ = .err,
        .mutable = true,
    };
}
