const std = @import("std");

const Ast = @import("Ast.zig");
const LlvmTyps = @import("LlvmTyps.zig");
const Typ = LlvmTyps.Typ;

const Info = @This();

typs: []Typ,

pub fn init(llvm_typs: *LlvmTyps, ast_info: Ast.Info) !Info {
    const typs = try llvm_typs.arena.allocator().alloc(Typ, ast_info.typ_ids);
    return .{
        .typs = typs,
    };
}
