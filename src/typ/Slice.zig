const std = @import("std");

const okc = @import("okc");

typ: *const okc.Typ,
sized: bool,
mutable: bool,

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.bral, .quiet);
    var sized = true;
    try ctx.maybe(okc.Parser.expect, .{ .star, .quiet }) orelse {
        sized = false;
    };
    try ctx.expect(.brar, .loud);
    var mutable = true;
    try ctx.maybe(okc.Parser.expect, .{ .mut, .quiet }) orelse {
        mutable = false;
    };
    const typ: okc.Typ = try .parse(ctx);
    const ptr = try okc.Typ.memo.box(typ, ctx.arena);
    return .{ .slice = .{
        .typ = ptr,
        .sized = true,
        .mutable = mutable,
    } };
}

pub fn eql(a: @This(), b: @This()) bool {
    return a.typ == b.typ and a.mutable == b.mutable;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self.typ));
    hasher.update(&.{@intFromBool(self.mutable)});
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll("[]");
    if (self.mutable) {
        try writer.writeAll("mut ");
    }
    try self.typ.format(writer);
}

pub fn checkField(
    self: @This(),
    mutable: bool,
    name: []const u8,
    location: okc.Location,
    failer: *okc.Failer,
) !okc.Expr.Info {
    if (std.mem.eql(u8, name, "ptr")) {
        return .{
            .typ = .{ .ptr = .{
                .typ = self.typ,
                .mutable = self.mutable,
            } },
            .mutable = mutable,
        };
    }
    if (std.mem.eql(u8, name, "len")) {
        return .{
            .typ = .{ .prime = .u64 },
            .mutable = mutable,
        };
    }
    failer.noField(location, name, .{ .slice = self });
    return .{
        .typ = .err,
        .mutable = true,
    };
}
