const std = @import("std");

const okc = @import("okc");

params: []const okc.Typ,
ret_typ: *const okc.Typ,

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.fun, .quiet);
    try ctx.expect(.parl, .loud);
    const params = try ctx.sep(okc.Typ.parse, .{});
    try ctx.expect(.parr, .loud);
    const ret_typ: okc.Typ = try .parse(ctx);
    const ptr = try okc.Typ.memo.box(ret_typ, ctx.arena);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

pub fn eql(a: @This(), b: @This()) bool {
    if (a.ret_typ != b.ret_typ) {
        return false;
    }
    for (a.params, b.params) |ap, bp| {
        if (!ap.eql(bp)) {
            return false;
        }
    }
    return true;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    for (self.params) |param| {
        param.hashIn(hasher);
    }
    self.ret_typ.hashIn(hasher);
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll("fn(");
    if (self.params.len != 0) {
        try self.params[0].format(writer);
        for (self.params[1..]) |param| {
            try writer.print(", {f}", .{param});
        }
    }
    try writer.print(") {f}", .{self.ret_typ});
}
