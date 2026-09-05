const std = @import("std");

const Ast = @import("Ast.zig");

pub const Call = struct {
    generics: []Ast.Typ,
    ret_typ: Ast.Typ,
};

const Info = @This();

typs: []Ast.Typ,
strucs: []Ast.Typ,
calls: []Call,

pub fn init(llvm_typs: *Ast.Typs, ast_info: Ast.Info) !Info {
    return .{
        .typs = try llvm_typs.arena.allocator().alloc(Ast.Typ, ast_info.typ_ids),
        .strucs = try llvm_typs.arena.allocator().alloc(Ast.Typ, ast_info.struc_ids),
        .calls = try llvm_typs.arena.allocator().alloc(Call, ast_info.call_ids),
    };
}
