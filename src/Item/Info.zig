const okc = @import("okc");

kind: Kind,
location: okc.Location,
used: bool = false,

pub fn checkUsage(self: @This(), name: []const u8, failer: *okc.Failer) void {
    if (self.used) {
        switch (self.kind) {
            .module => unreachable,
            .fun, .typ => {},
            .vari => |vari| vari.checkUsage(self.location, failer),
            .struc => |struc| struc.checkUsage(failer),
        }
    } else {
        failer.unused(self.location, name);
    }
}

pub const Kind = union(enum) {
    fun: *okc.Item.Fun.Header,
    struc: okc.Item.Struct.Info,
    vari: okc.Stmt.Declare.Info,
    module: okc.Module.Info,
    typ: okc.Typ,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .module => unreachable,
            .struc => |*struc| struc.deinit(),
            .fun, .vari, .typ => {},
        }
        self.* = undefined;
    }
};
