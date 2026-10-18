const okc = @import("okc");

expr: okc.Expr,
start: okc.Expr,
end: okc.Expr,

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
                    .mutable = true,
                } },
                .mutable = false,
            };
        },
    }
}
