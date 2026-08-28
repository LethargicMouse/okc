const std = @import("std");

const Ast = @import("Ast.zig");
const LlvmTyps = @import("LlvmTyps.zig");
const Typ = LlvmTyps.Typ;

const Info = @This();

typs: []Typ,
strucs: []Typ.Name,

pub fn init(llvm_typs: *LlvmTyps, ast_info: Ast.Info) !Info {
    const typs = try llvm_typs.arena.allocator().alloc(Typ, ast_info.typ_ids);
    const strucs = try llvm_typs.arena.allocator().alloc(Typ.Name, ast_info.struc_ids);
    return .{
        .typs = typs,
        .strucs = strucs,
    };
}
