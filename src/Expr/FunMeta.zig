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
    const solved = try typ.solve(ctx.arena);
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
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    header: okc.Item.Fun.Header,
) !okc.Expr.Info {
    var resolve_map: std.StringHashMap(okc.Typ) = .init(gpa);
    defer resolve_map.deinit();
    self.generics = try arena.alloc(okc.Typ, header.generics.len);
    @memset(self.generics, .any);
    for (header.generics, self.generics) |generic, *typ| {
        try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
    }
    const params = try gpa.alloc(okc.Typ, header.params.len);
    defer gpa.free(params);
    for (header.params, params) |param, *target| {
        target.* = try param.typ.resolve(resolve_map, arena);
    }
    const ret_typ = try header.ret_typ.resolve(resolve_map, arena);
    self.typ = .{ .fun = .{
        .params = try okc.Typ.memo.save(params, arena),
        .ret_typ = try okc.Typ.memo.box(ret_typ, arena),
    } };
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
