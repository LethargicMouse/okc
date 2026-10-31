const okc = @import("okc");

header: okc.Item.Fun.Header,

pub fn parseItem(ctx: *okc.Parser) !okc.Item {
    try ctx.expect(.ext, .quiet);
    const header: okc.Item.Fun.Header = try .parse(ctx, .loud);
    try ctx.expect(.semi, .loud);
    return .{
        .name = ctx.tmp_name,
        .location = ctx.tmp_location,
        .kind = .{ .ext_fun = .{ .header = header } },
    };
}

pub fn gen(self: @This(), name: []const u8, ctx: *okc.Codegen) !void {
    try ctx.writer.interface.print("\ndeclare {f} @{s}(", .{
        okc.Typ.LLPrinter{ .typ = self.header.ret_typ },
        name,
    });
    if (self.header.params.len != 0) {
        try ctx.writer.interface.print("{f}", .{okc.Typ.LLPrinter{ .typ = self.header.params[0].typ }});
        for (self.header.params[1..]) |param| {
            try ctx.writer.interface.print(", {f}", .{okc.Typ.LLPrinter{ .typ = param.typ }});
        }
    }
    try ctx.writer.interface.print(")", .{});
}
