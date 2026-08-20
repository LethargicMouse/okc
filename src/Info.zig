const std = @import("std");

const Ast = @import("Ast.zig");
const Typs = @import("Typs.zig");
const Typ = Typs.Typ;

const Info = @This();

typs: Typs,
lazy_typs: []*const Typ,

pub fn init(gpa: std.mem.Allocator, ast_info: Ast.Info) !Info {
    var typs = Typs.init(gpa);
    const lazy_typs = try typs.arena.allocator().alloc(*const Typ, ast_info.typ_ids);
    return .{
        .typs = typs,
        .lazy_typs = lazy_typs,
    };
}

pub fn deinit(info: *Info) void {
    info.typs.deinit();
}
