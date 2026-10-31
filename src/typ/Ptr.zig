const std = @import("std");

const okc = @import("okc");

typ: *const okc.Typ,
mutable: bool,

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.amp, .quiet);
    var mutable = false;
    if (try ctx.maybe(okc.Parser.expect, .{ .mut, .quiet })) |_| {
        mutable = true;
    }
    const typ: okc.Typ = try .parse(ctx);
    const ptr = try okc.Typ.memo.box(typ, ctx.arena);
    return .{ .ptr = .{
        .typ = ptr,
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
    if (self.mutable) {
        try writer.print("&mut {f}", .{self.typ});
    } else {
        try writer.print("&{f}", .{self.typ});
    }
}
