const std = @import("std");

const okc = @import("okc");

val: okc.Val,
inner_typ: okc.Typ,

pub fn load(self: @This(), ctx: Load) !u32 {
    const res = ctx.counter.next();
    try ctx.buffer.print(
        ctx.gpa,
        "\n  %t{} = load {f}, ptr {f}",
        .{ res, okc.Typ.LLPrinter{ .typ = self.inner_typ }, self.val },
    );
    return res;
}

pub fn loadTypVal(self: @This(), ctx: Load) !okc.Val.Typed {
    const tmp = try self.load(ctx);
    return .{
        .typ = self.inner_typ,
        .bare = .{ .tmp = tmp },
    };
}

pub fn toPtrTypVal(self: @This(), arena: std.mem.Allocator) !okc.Val.Typed {
    return .{
        .typ = .{ .ptr = .{
            .typ = try okc.Typ.memo.box(self.inner_typ, arena),
            .mutable = false,
        } },
        .bare = self.val,
    };
}

pub const Load = struct {
    gpa: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    counter: *okc.Counter,
};
