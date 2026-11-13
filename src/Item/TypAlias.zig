const okc = @import("okc");

typ: okc.Typ,

pub fn parseItem(ctx: *okc.Parser) !okc.Item {
    var public = false;
    if (try ctx.maybe(okc.Parser.expect, .{ .pubb, .quiet }) != null) public = true;
    try ctx.expect(.typ, .quiet);
    const location = ctx.getLocation();
    const name = try ctx.parseName(.loud);
    try ctx.expect(.equ, .loud);
    const typ: okc.Typ = try .parse(ctx);
    try ctx.expect(.semi, .loud);
    return .{
        .name = name,
        .public = public,
        .location = location,
        .kind = .{ .typ_alias = .{
            .typ = typ,
        } },
    };
}
