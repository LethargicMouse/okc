const okc = @import("okc");

fields: []const Field,

pub fn parse(ctx: *okc.Parser) !@This() {
    try ctx.expect(.ctx, .quiet);
    try ctx.expect(.curl, .loud);
    const fields = try ctx.sep(Field.parse, .{});
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    const endmode: okc.Parser.Mode = if (prev == .comma or prev == .curl) .quiet else .loud;
    try ctx.expect(.curr, endmode);
    return .{ .fields = fields };
}

pub const Field = struct {
    name: []const u8,
    expr: okc.Expr,
    location: okc.Location,

    pub fn parse(ctx: *okc.Parser) !@This() {
        const location = ctx.getLocation();
        const name = try ctx.parseName(.quiet);
        try ctx.expect(.equ, .loud);
        const expr = try okc.Expr.parse(ctx, .loud);
        return .{
            .name = name,
            .expr = expr,
            .location = location,
        };
    }
};
