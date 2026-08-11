const std = @import("std");

const Location = @import("Location.zig");

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
    location: Location,
};

pub const ArrayTyp = struct {
    len: []const u8,
    typ: Typ,
};

pub const Typ = union(enum) {
    prime: Prime,
    name: []const u8,
    ptr: *const Typ,
    array: *const ArrayTyp,

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
    bool,
    void,

    pub fn isNumber(prime: Prime) bool {
        switch (prime) {
            .i32, .u8, .u64 => return true,
            else => return false,
        }
    }
};

pub const Fun = struct {
    header: Header,
    statements: []const Statement,
};

pub const Statement = union(enum) {
    ret: Expr,
    expr: Expr,
    declare: Declare,
    assign: Assign,
    iff: If,
    whi: While,
    ignore: Expr,
    mut_declare: Declare,
};

pub const While = struct {
    branch: Branch,
};

pub const If = struct {
    branch: Branch,
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
    location: Location,
};

pub const Declare = struct {
    name: []const u8,
    expr: Expr,
    location: Location,
};

pub const Call = struct {
    name: []const u8,
    args: []const Expr,
    location: Location,
};

pub const Expr = union(enum) {
    literal_loc: LiteralLoc,
    call: Call,
    binary: *const Binary,
    field: *const Field,
    struc: StructExpr,

    pub fn location(expr: Expr) Location {
        switch (expr) {
            .literal_loc => |literal_loc| return literal_loc.location,
            .call => |call| return call.location,
            .binary => |binary| return binary.location,
            .field => |field| return field.location,
            .struc => |struc| return struc.location,
        }
    }
};

pub const StructExpr = struct {
    name: []const u8,
    fields: []const NewField,
    location: Location,
};

pub const NewField = struct {
    name: []const u8,
    expr: Expr,
};

pub const LiteralLoc = struct {
    literal: Literal,
    location: Location,
};

pub const Literal = union(enum) {
    int: []const u8,
    str: usize,
    vari: []const u8,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
    location: Location,
};

pub const Binary = struct {
    left: Expr,
    op: BinOp,
    right: Expr,
    location: Location,
};

pub const BinOp = enum {
    andb,
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
            .andb => return 1,
            .add, .sub => return 2,
            .mul, .div, .rem => return 3,
        }
    }
};

pub const Struct = struct {
    name: []const u8,
    fields: []const FieldDecl,
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: Typ,
};

const Ast = @This();

ext_funs: []const ExtFun,
funs: []const Fun,
strucs: []const Struct,
strs: []const []const u8,
arena: std.heap.ArenaAllocator,

pub fn deinit(ast: *Ast) void {
    ast.arena.deinit();
    ast.* = undefined;
}
