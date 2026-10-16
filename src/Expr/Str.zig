const std = @import("std");

const okc = @import("okc");

bare: []const u8,

pub fn check(arena: std.mem.Allocator) !okc.Expr.Info {
    const ptr = try okc.Typ.memo.box(.{ .prime = .u8 }, arena);
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .mutable = false,
        } },
        .mutable = false,
    };
}
