const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,
vari: okc.Expr.Var,

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
        return norm.slice.checkField(info.mutable, self.vari.name, location, ctx.failer);
    }
    if (norm == .err) {
        return err;
    }
    if (norm == .typ) {
        const name = self.expr.kind.vari.name;
        const item = ctx.items.getPtr(name).?;
        item.used = true;
        const decl = item.getTypDecl(.{ .name = name }, self.expr.location, ctx) orelse return err;
        if (decl.variants.getPtr(self.vari.name)) |variant| {
            variant.used = true;
            return .{
                .typ = .{ .name = .{ .name = name } },
                .mutable = false,
            };
        } else {
            const inner_ctx = ctx.inside(.{ .name = .{ .name = name } }) orelse {
                ctx.failer.noMember(location, self.vari.name, norm);
                return err;
            };
            return self.vari.check(location, if (hint_mutable) .mutable else .constant, inner_ctx);
        }
    }
    const name = norm.getName() orelse {
        ctx.failer.noField(location, self.vari.name, norm);
        return err;
    };
    const item = ctx.items.get(name.name) orelse {
        ctx.failer.noField(location, self.vari.name, norm);
        return err;
    };
    const struc = if (item.kind == .typ) item.kind.typ else {
        ctx.failer.noField(location, self.vari.name, norm);
        return err;
    };
    const fiel = struc.fields.getPtr(self.vari.name) orelse {
        ctx.failer.noField(location, self.vari.name, norm);
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
