const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,
name: []const u8,

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint_mutable: bool,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    var info = try self.expr.check(.{ .mutable = hint_mutable }, ctx);
    const err = okc.Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    var norm = info.typ.normalise();
    if (norm == .ptr) {
        info.mutable = norm.ptr.mutable;
        norm = norm.ptr.typ.normalise();
    }
    if (norm == .slice) {
        return norm.slice.checkField(info.mutable, self.name, location, ctx.failer);
    }
    if (norm == .err) {
        return err;
    }
    const name = norm.getName() orelse {
        ctx.failer.noField(location, self.name, norm);
        return err;
    };
    const item = ctx.items.get(name.name) orelse {
        ctx.failer.noField(location, self.name, norm);
        return err;
    };
    const struc = if (item.kind == .struc) item.kind.struc else {
        ctx.failer.noField(location, self.name, norm);
        return err;
    };
    const fiel = struc.fields.getPtr(self.name) orelse {
        ctx.failer.noField(location, self.name, norm);
        return err;
    };
    fiel.used = true;
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    return .{
        .typ = try fiel.typ.resolve(resolve_map, ctx.arena),
        .mutable = info.mutable,
    };
}
