const std = @import("std");

const okc = @import("okc");

bare: *okc.Expr.Struct,
typ: okc.Typ.Name,

pub fn check(
    self: @This(),
    location: okc.Location,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    std.log.debug("check struct expr of `{f}`", .{self.typ});
    const err = okc.Expr.Info{
        .typ = .err,
        .mutable = false,
    };
    const item = ctx.items.getPtr(self.typ.name) orelse {
        ctx.failer.notDeclared(location, self.typ.name, ctx.mod_name);
        return err;
    };
    item.used = true;
    const decl = item.getTypDecl(self.typ, ctx) orelse {
        ctx.failer.notCompound(location, self.typ);
        return err;
    };
    const generics = try ctx.arena.allocator().alloc(okc.Typ, decl.generics.len);
    if (self.typ.generics.len == 0) {
        @memset(generics, .any);
    } else {
        @memcpy(generics, self.typ.generics);
    }
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    for (decl.generics, generics) |generic, *typ| {
        try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
    }
    for (self.bare.fields) |*field| {
        try field.check(.{ .name = self.typ }, decl.fields, resolve_map, ctx);
    }
    var iter = decl.fields.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.defaulted) {
            continue;
        }
        var not_init = true;
        for (self.bare.fields) |field| {
            if (std.mem.eql(u8, entry.key_ptr.*, field.name)) {
                not_init = false;
                break;
            }
        }
        if (not_init) {
            ctx.failer.notInit(location, entry.key_ptr.*, self.typ.name);
        }
    }
    self.bare.typ = okc.Typ{ .name = .{
        .generics = try okc.Typ.memo.save(generics, ctx.arena),
        .name = self.typ.name,
    } };
    return .{
        .typ = self.bare.typ,
        .mutable = false,
    };
}
