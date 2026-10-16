const std = @import("std");

const okc = @import("okc");

val: u64,
typ: okc.Typ = .int,

pub fn check(self: *@This()) !okc.Expr.Info {
    std.debug.assert(self.typ == .int);
    return .{
        .typ = .{ .lazy = .from(&self.typ) },
        .mutable = false,
    };
}
