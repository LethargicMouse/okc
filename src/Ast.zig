const std = @import("std");

pub const ExtFun = struct {
    header: Header,
};

pub const Header = struct {
    name: []const u8,
    params: []const Param,
    ret_typ: Typ,
};

pub const Param = struct {
    name: []const u8,
    typ: Typ,
};

pub const Typ = union(enum) {
    prime: Prime,
    name: []const u8,
    ptr: *const Typ,

    pub fn fromName(name: []const u8) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = name };
    }
};

pub const Prime = enum {
    u8,
    i32,
    u64,
};

pub const Fun = struct {
    header: Header,
    statements: []const Statement,
};

pub const Statement = union(enum) {
    ret: Expr,
    expr: Expr,
    let: Let,
    assign: Assign,
    iff: If,
    whi: While,
};

pub const While = struct {
    branch: Branch,
};

pub const If = struct {
    cond_branch: Branch,
    else_ifs: []const Branch,
    else_branch: []const Statement,
};

pub const Branch = struct {
    condition: Expr,
    statements: []const Statement,
};

pub const Assign = struct {
    name: []const u8,
    expr: Expr,
};

pub const Let = struct {
    name: []const u8,
    expr: Expr,
};

pub const Call = struct {
    name: []const u8,
    args: []const Expr,
};

pub const Expr = union(enum) {
    int: []const u8,
    str: usize,
    call: Call,
    vari: []const u8,
    binary: *const Binary,
    field: *const Field,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
};

pub const Binary = struct {
    left: Expr,
    op: BinOp,
    right: Expr,
};

pub const BinOp = enum {
    equ,
    add,
    sub,
    mul,
    div,
    les,
    rem,

    pub fn prior(bin_op: BinOp) u8 {
        switch (bin_op) {
            .equ, .les => return 0,
            .add, .sub => return 1,
            .mul, .div, .rem => return 2,
        }
    }
};

const Ast = @This();

ext_funs: []const ExtFun,
funs: []const Fun,
strs: []const []const u8,
arena: std.heap.ArenaAllocator,

pub fn deinit(ast: Ast) void {
    ast.arena.deinit();
}
