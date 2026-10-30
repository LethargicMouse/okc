const okc = @import("okc");

expr: okc.Expr,
start: okc.Expr,
end: okc.Expr,

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.expr.genRef(ctx);
    const start = try self.start.gen(ctx);
    const end = try self.end.gen(ctx);
    const ptr_ref = try ref.genElem(start, ctx);
    const ptr = try ptr_ref.toPtrTypVal(ctx.arena);
    const len = try okc.Expr.Binary.genOnVals(.sub, start.typ, end.bare, start.bare, ctx);
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = try okc.Typ.memo.box(ptr_ref.inner_typ, ctx.arena),
            .sized = true,
            .mutable = false,
        } },
        .bare = .undef,
    };
    try res.genIV(ptr, 0, ctx);
    try res.genIV(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .tmp = len },
    }, 1, ctx);
    return res;
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    const info = try self.expr.check(.{}, ctx);
    const start = try self.start.check(.{}, ctx);
    _ = start.typ.unify(.{ .prime = .u64 }, self.start.location, ctx.failer);
    const end = try self.end.check(.{}, ctx);
    _ = end.typ.unify(.{ .prime = .u64 }, self.end.location, ctx.failer);
    switch (info.typ.normalise()) {
        .array => |array| return .{
            .typ = .{ .slice = .{
                .typ = array.typ,
                .sized = true,
                .mutable = info.mutable,
            } },
            .mutable = false,
        },
        .slice => return .{
            .typ = info.typ,
            .mutable = info.mutable,
        },
        else => |typ| {
            ctx.failer.fail(location, "cannot take slice of `{f}`", .{typ});
            return .{
                .typ = .{ .slice = .{
                    .typ = try okc.Typ.memo.box(.err, ctx.arena),
                    .sized = true,
                    .mutable = true,
                } },
                .mutable = false,
            };
        },
    }
}
