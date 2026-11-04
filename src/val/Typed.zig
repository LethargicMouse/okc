const std = @import("std");

const okc = @import("okc");

bare: okc.Val,
typ: okc.Typ,

pub fn toStack(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    if (self.typ.getName()) |name| {
        try okc.Item.TypDecl.genNamed(name, ctx);
    }
    const tmp = ctx.counter.next();
    try ctx.extra_buffer.print(
        ctx.gpa,
        "\n  %t{} = alloca {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = self.typ } },
    );
    try self.store(.{ .tmp = tmp }, ctx);
    return .{
        .val = .{ .tmp = tmp },
        .inner_typ = self.typ,
    };
}

pub fn store(self: @This(), val: okc.Val, ctx: *okc.Codegen) !void {
    try ctx.buffer.print(ctx.gpa, "\n  store {f}, ptr {f}", .{ self, val });
}

pub fn genIV(self: *@This(), val: @This(), index: u64, ctx: *okc.Codegen) !void {
    const tmp = ctx.counter.next();
    try ctx.buffer.print(
        ctx.gpa,
        "\n  %t{} = insertvalue {f}, {f}, {d}",
        .{ tmp, self, val, index },
    );
    self.bare = .{ .tmp = tmp };
}

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("{f} {f}", .{ okc.Typ.LLPrinter{ .typ = self.typ }, self.bare });
}

pub fn int(n: u64) okc.Val.Typed {
    return .{
        .typ = .{ .prime = .i32 },
        .bare = .{ .int = n },
    };
}
