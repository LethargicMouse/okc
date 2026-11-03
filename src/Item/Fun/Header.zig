const okc = @import("okc");

generics: []const okc.Item.Generic,
params: []okc.Item.Fun.Param,
context: []okc.Item.Fun.Param,
ret_typ: okc.Typ,

pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !okc.Item.Fun.Header {
    try ctx.expect(.fun, mode);
    ctx.tmp_location = ctx.getLocation();
    ctx.tmp_name = try ctx.parseName(.loud);
    const generics = try ctx.maybe(okc.Item.parseGenerics, .{}) orelse &.{};
    try ctx.expect(.parl, .loud);
    const params = try ctx.sep(okc.Item.Fun.Param.parse, .{});
    try ctx.expect(.parr, .loud);
    const context = try ctx.maybe(parseContext, .{}) orelse @constCast(&.{});
    const ret_typ: okc.Typ = try .parse(ctx);
    return .{
        .generics = generics,
        .params = params,
        .context = context,
        .ret_typ = ret_typ,
    };
}

pub fn parseContext(ctx: *okc.Parser) ![]okc.Item.Fun.Param {
    try ctx.expect(.ctx, .quiet);
    try ctx.expect(.curl, .loud);
    const params = try ctx.sep(okc.Item.Fun.Param.parse, .{});
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    const endmode: okc.Parser.Mode = if (prev == .comma or prev == .curl) .quiet else .loud;
    try ctx.expect(.curr, endmode);
    return params;
}

pub fn check(self: *@This(), ctx: okc.Item.Check) !void {
    var generics_checker: okc.Item.Generic.Checker = try .init(ctx.gpa, self.generics);
    defer generics_checker.deinit(ctx.gpa);
    const typ_check = ctx.typCheckCtx(&generics_checker);
    for (self.params) |*param| {
        param.typ = try param.typ.check(typ_check);
    }
    for (self.context) |*param| {
        param.typ = try param.typ.check(typ_check);
    }
    self.ret_typ = try self.ret_typ.check(typ_check);
    generics_checker.checkUsage(ctx.failer);
}
