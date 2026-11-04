const std = @import("std");

const okc = @import("okc");

typ: *const okc.Typ,
sized: bool,
mutable: bool,

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.bral, .quiet);
    var sized = false;
    try ctx.maybe(okc.Parser.expect, .{ .star, .quiet }) orelse {
        sized = true;
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
        .sized = sized,
        .mutable = mutable,
    } };
}

pub fn eql(a: @This(), b: @This()) bool {
    return a.typ == b.typ and a.mutable == b.mutable and a.sized == b.sized;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self.typ));
    hasher.update(&.{ @intFromBool(self.mutable), @intFromBool(self.sized) });
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeByte('[');
    if (!self.sized) {
        try writer.writeByte('*');
    }
    try writer.writeByte(']');
    if (self.mutable) {
        try writer.writeAll("mut ");
    }
    try self.typ.format(writer);
}
