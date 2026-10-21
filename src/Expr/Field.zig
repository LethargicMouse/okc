const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,
vari: okc.Expr.Var,

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    var vari = try self.expr.genRef(ctx);
    if (vari.inner_typ == .typ) {
        const name = self.expr.kind.vari.name;
        const item = ctx.module.items.get(name).?;
        switch (item) {
            .typ_decl => |typ| {
                try typ.gen(.{ .name = name }, ctx);
                const index = ctx.typ_decls.get(.{ .name = name }).?
                    .variants.get(self.vari.name).?;
                var res: okc.Val.Typed = .{
                    .typ = .{ .name = .{ .name = name } },
                    .bare = .undef,
                };
                try ctx.genIV(&res, .{
                    .typ = .{ .prime = .i32 },
                    .bare = .{ .int = index },
                }, 0);
                return ctx.toStack(res);
            },
            .use => {
                const old = ctx.module;
                defer ctx.module = old;
                ctx.module = try ctx.getModule(name);
                return self.vari.genRef(ctx);
            },
            else => unreachable,
        }
    }
    if (vari.inner_typ == .ptr) {
        const tmp = try vari.load(ctx.loadCtx());
        vari = .{
            .inner_typ = vari.inner_typ.ptr.typ.*,
            .val = .{ .tmp = tmp },
        };
    }
    if (vari.inner_typ == .array) {
        std.debug.assert(std.mem.eql(u8, self.vari.name, "len"));
        return ctx.toStack(.{
            .typ = .{ .prime = .u64 },
            .bare = .{ .int = vari.inner_typ.array.len },
        });
    }
    const info = vari.inner_typ.getFieldGenInfo(self.vari.name, ctx.typ_decls);
    const tmp = try vari.genGEPIB(.int(info.index), ctx.loadCtx());
    return .{
        .inner_typ = info.typ,
        .val = .{ .tmp = tmp },
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx.loadCtx());
}

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
        return self.vari.checkIn(
            .{ .name = name },
            location,
            if (hint_mutable) .mutable else .constant,
            ctx,
        );
    }
    const name = norm.getName() orelse {
        ctx.failer.noField(location, self.vari.name, norm);
        return err;
    };
    const item = ctx.items.get(name.name) orelse {
        ctx.failer.noField(location, self.vari.name, norm);
        return err;
    };
    const struc = if (item.kind == .typ_decl) item.kind.typ_decl else {
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
