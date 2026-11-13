const std = @import("std");

const okc = @import("okc");

// mutable cuz lazies that are returned by `fillFromHeader` point here
generics: []okc.Typ,
typ: okc.Typ.Fun,

pub fn gen(self: @This(), fun_name: []const u8, ctx: *okc.Codegen) !okc.Val.Typed {
    const generics = try ctx.gpa.dupe(okc.Typ, self.generics);
    defer ctx.gpa.free(generics);
    for (generics) |*typ| {
        typ.* = try typ.solve(ctx.gpa, ctx.arena);
        typ.* = try typ.resolve(.{
            .gpa = ctx.gpa,
            .arena = ctx.arena,
            .map = ctx.resolve_map,
        });
    }
    var name = okc.Typ.Name{
        .name = fun_name,
        .generics = try okc.Typ.memo.save(generics, ctx.arena),
    };
    if (ctx.module.items.get(fun_name).? == .ext_fun) {
        name.generics = &.{};
    }
    const typ: okc.Typ = .{ .fun = self.typ };
    const solved = try typ.solve(ctx.gpa, ctx.arena);
    const resolved = try solved.resolve(.{
        .gpa = ctx.gpa,
        .arena = ctx.arena,
        .map = ctx.resolve_map,
    });
    try ctx.fun_queue.append(ctx.gpa, .{
        .module = ctx.module,
        .name = name,
        .fun = resolved.fun,
    });
    return .{
        .typ = solved,
        .bare = .{ .global = name },
    };
}

pub fn fillFromHeader(
    self: *@This(),
    header: okc.Item.Fun.Header,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    const mod_generics = if (ctx.items.get(ctx.mod_name)) |item| item.kind.typ_decl.generics else &.{};
    std.log.debug("ref header {any} with mod generics {any}", .{ header, mod_generics });
    self.generics = try ctx.arena.allocator().alloc(okc.Typ, header.generics.len + mod_generics.len);
    @memset(self.generics, .any);
    for (header.generics, self.generics[0..header.generics.len]) |generic, *typ| {
        try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
    }
    for (mod_generics, self.generics[header.generics.len..]) |generic, *typ| {
        try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
    }
    const params = try ctx.gpa.alloc(okc.Typ, header.params.len);
    defer ctx.gpa.free(params);
    for (header.params, params) |param, *target| {
        target.* = try param.typ.resolve(.{ .gpa = ctx.gpa, .arena = ctx.arena, .map = resolve_map });
    }
    const ret_typ = try header.ret_typ.resolve(.{ .gpa = ctx.gpa, .arena = ctx.arena, .map = resolve_map });
    self.typ = .{
        .params = try okc.Typ.memo.save(params, ctx.arena),
        .ret_typ = try okc.Typ.memo.box(ret_typ, ctx.arena),
        .context = header.context,
    };
    std.log.debug("got fun ref {f}", .{self.typ});
    return .{
        .typ = .{ .fun = self.typ },
        .mutable = false,
    };
}
