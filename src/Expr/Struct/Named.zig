const okc = @import("okc");

bare: okc.Expr.Struct,
name: []const u8,

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    return self.bare.typed(.{ .name = self.name }).check(location, ctx);
}
