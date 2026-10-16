const okc = @import("okc");

typ: okc.Typ,

pub fn check(typ: okc.Typ) !okc.Expr.Info {
    _ = typ;
    return .{
        .typ = .{ .prime = .u64 },
        .mutable = false,
    };
}
