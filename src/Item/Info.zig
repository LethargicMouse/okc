const okc = @import("okc");

kind: Kind,
location: okc.Location,
used: bool = false,

pub fn getStruct(self: @This(), typ: okc.Typ.Name, location: okc.Location, ctx: okc.Expr.Check) ?okc.Item.Typ.Info {
    if (self.kind == .struc) {
        return self.kind.struc;
    } else if (self.kind == .module) {
        if (ctx.modules.get(typ.name).?.items.get(typ.name)) |item| {
            return item.getStruct(typ, location, ctx);
        } else {
            ctx.failer.notStruct(location, .{ .name = typ });
            return null;
        }
    } else {
        ctx.failer.notStruct(location, .{ .name = typ });
        return null;
    }
}

pub fn checkUsage(self: @This(), name: []const u8, failer: *okc.Failer) void {
    if (self.used) {
        switch (self.kind) {
            .fun, .typ, .module => {},
            .vari => |vari| vari.checkUsage(self.location, failer),
            .struc => |struc| struc.checkUsage(failer),
        }
    } else {
        failer.unused(self.location, name);
    }
}

pub const Kind = union(enum) {
    fun: *okc.Item.Fun.Header,
    module: okc.Module.Info,
    struc: okc.Item.Typ.Info,
    typ: okc.Typ,
    vari: okc.Stmt.Declare.Info,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .struc => |*struc| struc.deinit(),
            .fun, .vari, .typ, .module => {},
        }
        self.* = undefined;
    }
};
