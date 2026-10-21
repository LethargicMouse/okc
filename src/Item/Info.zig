const okc = @import("okc");

kind: Kind,
location: okc.Location,
used: bool = false,

pub fn getTypDecl(
    self: @This(),
    typ: okc.Typ.Name,
    ctx: okc.Expr.Check,
) ?okc.Item.TypDecl.Info {
    if (self.kind == .typ_decl) {
        return self.kind.typ_decl;
    } else if (self.kind == .module) {
        if (ctx.modules.get(typ.name).?.items.get(typ.name)) |item| {
            return item.getTypDecl(typ, ctx);
        } else {
            return null;
        }
    } else {
        return null;
    }
}

pub fn checkUsage(self: @This(), name: []const u8, failer: *okc.Failer) void {
    if (self.used) {
        switch (self.kind) {
            .fun, .alias, .module => {},
            .vari => |vari| vari.checkUsage(self.location, failer),
            .typ_decl => |typ| typ.checkUsage(failer),
        }
    } else {
        failer.unused(self.location, name);
    }
}

pub const Kind = union(enum) {
    alias: okc.Item.TypAlias,
    fun: *okc.Item.Fun.Header,
    module: okc.Module.Info,
    typ_decl: okc.Item.TypDecl.Info,
    vari: okc.Stmt.Declare.Info,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .typ_decl => |*struc| struc.deinit(),
            .fun, .vari, .alias, .module => {},
        }
        self.* = undefined;
    }
};
