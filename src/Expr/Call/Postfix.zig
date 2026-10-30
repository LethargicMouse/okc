const okc = @import("okc");

args: []okc.Expr,
context: okc.Expr.Call.Context,

pub fn parse(ctx: *okc.Parser) !@This() {
    try ctx.expect(.parl, .quiet);
    const args = try ctx.sep(okc.Expr.parse, .{.loud});
    const location = ctx.getLocation();
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    const endmode: okc.Parser.Mode = if (prev == .comma or prev == .parl) .quiet else .loud;
    try ctx.expect(.parr, endmode);
    const context = try ctx.maybe(okc.Expr.Call.Context.parse, .{}) orelse
        okc.Expr.Call.Context{ .fields = &.{} };
    ctx.tmp_location = location;
    return .{
        .args = args,
        .context = context,
    };
}
