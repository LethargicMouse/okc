const std = @import("std");

const okc = @import("okc");

typ: *const okc.Typ,

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.quest, .quiet);
    const typ = try okc.Typ.parse(ctx);
    return .{ .maybe = .{ .typ = try okc.Typ.memo.box(typ, ctx.arena) } };
}

pub fn eql(self: @This(), other: @This()) bool {
    return self.typ == other.typ;
}

pub fn hashIn(self: @This(), hash: *std.hash.Wyhash) void {
    hash.update(std.mem.asBytes(&self.typ));
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.print("?{f}", .{self.typ});
}
