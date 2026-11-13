const std = @import("std");

const okc = @import("okc");

typ: okc.Typ = .any,

pub fn gen(self: @This()) !okc.Val.Typed {
    return .{ .typ = self.typ, .bare = .undef };
}

pub fn check(
    self: *@This(),
    hint: okc.Typ,
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
) !okc.Expr.Info {
    self.typ = try hint.solve(gpa, arena);
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
