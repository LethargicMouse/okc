const okc = @import("okc");

expr: okc.Expr,

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    const val = try self.expr.gen(ctx);
    return .{
        .inner_typ = val.typ.ptr.typ.*,
        .val = val.bare,
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx);
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    const info = try self.expr.check(.{}, ctx);
    const norm = info.typ.normalise();
    const err = okc.Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    switch (norm) {
        .ptr => |ptr| {
            return .{
                .typ = ptr.typ.*,
                .mutable = ptr.mutable,
            };
        },
        .err => return err,
        .prime, .name, .any, .array, .slice, .fun, .int, .loc_name, .typ => {
            ctx.failer.fail(location, "cannot dereference type `{f}`", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}
