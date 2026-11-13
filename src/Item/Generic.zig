const okc = @import("okc");

name: []const u8,
location: okc.Location,

pub fn parse(ctx: *okc.Parser) !okc.Item.Generic {
    const location = ctx.getLocation();
    const name = try ctx.parseName(.loud);
    return .{
        .name = name,
        .location = location,
    };
}
