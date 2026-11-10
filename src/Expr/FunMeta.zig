const std = @import("std");

const okc = @import("okc");

generics: []okc.Typ,
typ: okc.Typ,

pub fn gen(self: @This(), fun_name: []const u8, ctx: *okc.Codegen) !okc.Val.Typed {
    var name = okc.Typ.Name{
        .name = fun_name,
        .generics = self.generics,
    };
    if (ctx.module.items.get(fun_name).? == .ext_fun) {
        name.generics = &.{};
    }
    const typ: okc.Typ = .{ .fun = self.typ.fun };
    const solved = try typ.solve(ctx.gpa, ctx.arena);
    try ctx.fun_queue.append(ctx.gpa, .{
        .module = ctx.module,
        .name = name,
        .fun = solved.fun,
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
    std.log.debug("ref header {any}", .{header});
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    self.generics = try ctx.arena.allocator().alloc(okc.Typ, header.generics.len);
    @memset(self.generics, .any);
    for (header.generics, self.generics) |generic, *typ| {
        try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
    }
    const params = try ctx.gpa.alloc(okc.Typ, header.params.len);
    defer ctx.gpa.free(params);
    for (header.params, params) |param, *target| {
        target.* = try param.typ.resolve(.{ .gpa = ctx.gpa, .arena = ctx.arena, .map = resolve_map });
    }
    const ret_typ = try header.ret_typ.resolve(.{ .gpa = ctx.gpa, .arena = ctx.arena, .map = resolve_map });
    self.typ = .{ .fun = .{
        .params = try okc.Typ.memo.save(params, ctx.arena),
        .ret_typ = try okc.Typ.memo.box(ret_typ, ctx.arena),
        .context = header.context,
    } };
    std.log.debug("got fun ref {f}", .{self.typ});
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
