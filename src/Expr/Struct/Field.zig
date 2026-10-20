const std = @import("std");

const okc = @import("okc");

name: []const u8,
expr: okc.Expr,
location: okc.Location,

pub fn check(
    self: *@This(),
    struc_typ: okc.Typ,
    decl_fields: std.StringHashMap(okc.Item.Typ.Field.Info),
    resolve_map: std.StringHashMap(okc.Typ),
    ctx: okc.Expr.Check,
) !void {
    const f_decl = decl_fields.get(self.name) orelse {
        ctx.failer.noField(self.location, self.name, struc_typ);
        return;
    };
    const decl_typ = try f_decl.typ.resolve(resolve_map, ctx.arena);
    const info = try self.expr.check(.{ .typ = decl_typ }, ctx);
    _ = info.typ.unify(decl_typ, self.expr.location, ctx.failer);
}
