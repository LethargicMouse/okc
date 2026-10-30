const std = @import("std");

const okc = @import("okc");

val: u64,
typ: okc.Typ = .int,

pub fn gen(self: @This()) okc.Val.Typed {
    return .{
        .typ = self.typ.normalise(),
        .bare = .{ .int = self.val },
    };
}

pub fn check(self: *@This()) !okc.Expr.Info {
    std.debug.assert(self.typ == .int);
    return .{
        .typ = .{ .lazy = .from(&self.typ) },
        .mutable = false,
    };
}
