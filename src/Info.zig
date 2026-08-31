const std = @import("std");

const Ast = @import("Ast.zig");
const LlvmTyps = @import("LlvmTyps.zig");
const Typ = LlvmTyps.Typ;

pub const Call = struct {
    generics: []Typ,
    ret_typ: Typ,
};

const Info = @This();

typs: []Typ,
strucs: []Typ.Name,
calls: []Call,

pub fn init(llvm_typs: *LlvmTyps, ast_info: Ast.Info) !Info {
    return .{
        .typs = try llvm_typs.arena.allocator().alloc(Typ, ast_info.typ_ids),
        .strucs = try llvm_typs.arena.allocator().alloc(Typ.Name, ast_info.struc_ids),
        .calls = try llvm_typs.arena.allocator().alloc(Call, ast_info.call_ids),
    };
}
