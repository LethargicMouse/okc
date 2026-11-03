const okc = @import("okc");

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
