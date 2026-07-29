const std = @import("std");

pub const Fun = struct {
    name: []const u8,
    statements: []const Statement,

    fn deinit(fun: Fun, gpa: std.mem.Allocator) void {
        gpa.free(fun.statements);
    }
};

pub const Statement = union(enum) {
    ret: Expr,
};

pub const Expr = union(enum) {
    int: []const u8,
};

const Ast = @This();

funs: []const Fun,

pub fn deinit(ast: *Ast, gpa: std.mem.Allocator) void {
    for (ast.funs) |fun| {
        fun.deinit(gpa);
    }
    gpa.free(ast.funs);
}
