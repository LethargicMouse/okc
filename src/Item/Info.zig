const okc = @import("okc");

kind: Kind,
location: okc.Location,
used: bool = false,

pub fn checkUsage(self: @This(), name: []const u8, failer: *okc.Failer) void {
    if (self.used) {
        switch (self.kind) {
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
    typ: okc.Typ,
    vari: okc.Stmt.Declare.Info,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .struc => |*struc| struc.deinit(),
            .fun, .vari, .typ => {},
        }
        self.* = undefined;
    }
};
