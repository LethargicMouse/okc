const okc = @import("okc");

generics: []const okc.Item.Generic,
params: []Param,
context: []Param,
ret_typ: okc.Typ,

pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !okc.Item.Fun.Header {
    try ctx.expect(.fun, mode);
    ctx.tmp_location = ctx.getLocation();
    ctx.tmp_name = try ctx.parseName(.loud);
    const generics = try ctx.maybe(okc.Item.parseGenerics, .{}) orelse &.{};
    try ctx.expect(.parl, .loud);
    const params = try ctx.sep(Param.parse, .{});
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

pub fn parseContext(ctx: *okc.Parser) ![]Param {
    try ctx.expect(.ctx, .quiet);
    try ctx.expect(.curl, .loud);
    const params = try ctx.sep(Param.parse, .{});
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

pub const Param = struct {
    name: []const u8,
    typ: okc.Typ,
    location: okc.Location,

    pub fn parse(ctx: *okc.Parser) !@This() {
        const location = ctx.getLocation();
        const name = try ctx.parseName(.loud);
        try ctx.expect(.colon, .loud);
        const typ: okc.Typ = try .parse(ctx);
        return .{
            .name = name,
            .typ = typ,
            .location = location,
        };
    }

    pub fn gen(typ: okc.Typ, ctx: *okc.Codegen) !okc.Val.Typed {
        const tmp = ctx.counter.next();
        try ctx.extra_buffer.print(
            ctx.gpa,
            "{f} %t{}",
            .{ okc.Typ.LLPrinter{ .typ = typ }, tmp },
        );
        return .{ .typ = typ, .bare = .{ .tmp = tmp } };
    }
};
