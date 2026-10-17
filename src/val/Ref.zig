const std = @import("std");

const okc = @import("okc");

val: okc.Val,
inner_typ: okc.Typ,

pub fn toPtrTypVal(self: @This(), arena: std.mem.Allocator) !okc.Val.Typed {
    return .{
        .typ = .{ .ptr = .{
            .typ = try okc.Typ.memo.box(self.inner_typ, arena),
            .mutable = false,
        } },
        .bare = self.val,
    };
}
