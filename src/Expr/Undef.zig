const std = @import("std");

const okc = @import("okc");

typ: okc.Typ = .any,

pub fn gen(self: @This()) !okc.Val.Typed {
    return .{ .typ = self.typ, .bare = .undef };
}

pub fn check(self: *@This(), typ: okc.Typ, arena: std.mem.Allocator) !okc.Expr.Info {
    self.typ = try typ.solve(arena);
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
