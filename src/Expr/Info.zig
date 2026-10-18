const okc = @import("okc");

typ: okc.Typ,
mutable: bool,

pub fn getElem(self: @This(), location: okc.Location, failer: *okc.Failer) ?@This() {
    switch (self.typ.normalise()) {
        .array => |array| return .{
            .typ = array.typ.*,
            .mutable = self.mutable,
        },
        .slice => |slice| return .{
            .typ = slice.typ.*,
            .mutable = slice.mutable,
        },
        .err => return null,
        .prime, .name, .loc_name, .ptr, .any, .fun, .int, .typ => {
            failer.fail(location, "type `{f}` does not support indexing", .{self.typ});
            return null;
        },
        .lazy => unreachable,
    }
}

pub const Call = struct {
    typ: okc.Typ,
    args: []okc.Expr,
    maybe_first: ?okc.Expr.Info.Located,
    location: okc.Location,

    pub fn check(self: @This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
        const fun = self.typ.getFun(self.location, ctx.failer) orelse {
            for (self.args) |*arg| {
                _ = try arg.check(.{}, ctx);
            }
            return .{
                .typ = .err,
                .mutable = false,
            };
        };
        // to propagate hint to generics
        _ = fun.ret_typ.unifyOrNull(hint, .active);
        var params = fun.params;
        if (self.maybe_first) |first| {
            params = fun.params[1..];
            _ = first.bare.typ.unify(fun.params[0], self.location, ctx.failer);
        }
        for (self.args, params) |*arg, param| {
            const info = try arg.check(.{ .typ = param }, ctx);
            _ = info.typ.unify(param, arg.location, ctx.failer);
        }
        return .{
            .typ = fun.ret_typ.*,
            .mutable = false,
        };
    }
};

pub const Located = struct {
    bare: okc.Expr.Info,
    location: okc.Location,
};
