const okc = @import("okc");

kind: Kind,
location: okc.Location,
used: bool = false,

pub fn getTypDecl(
    self: @This(),
    typ: okc.Typ.Name,
    location: okc.Location,
    ctx: okc.Expr.Check,
) ?okc.Item.Typ.Info {
    if (self.kind == .typ) {
        return self.kind.typ;
    } else if (self.kind == .module) {
        if (ctx.modules.get(typ.name).?.items.get(typ.name)) |item| {
            return item.getTypDecl(typ, location, ctx);
        } else {
            ctx.failer.notCompound(location, typ);
            return null;
        }
    } else {
        ctx.failer.notCompound(location, typ);
        return null;
    }
}

pub fn checkUsage(self: @This(), name: []const u8, failer: *okc.Failer) void {
    if (self.used) {
        switch (self.kind) {
            .fun, .alias, .module => {},
            .vari => |vari| vari.checkUsage(self.location, failer),
            .typ => |typ| typ.checkUsage(failer),
        }
    } else {
        failer.unused(self.location, name);
    }
}

pub const Kind = union(enum) {
    fun: *okc.Item.Fun.Header,
    module: okc.Module.Info,
    typ: okc.Item.Typ.Info,
    alias: okc.Item.TypAlias,
    vari: okc.Stmt.Declare.Info,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .typ => |*struc| struc.deinit(),
            .fun, .vari, .alias, .module => {},
        }
        self.* = undefined;
    }
};
