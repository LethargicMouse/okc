const okc = @import("okc");

name: []const u8,
location: okc.Location,

pub fn parse(ctx: *okc.Parser) !@This() {
    const location = ctx.getLocation();
    const name = try ctx.parseName(.quiet);
    return .{
        .name = name,
        .location = location,
    };
}

pub const Info = struct {
    used: bool = false,
    location: okc.Location,
};
