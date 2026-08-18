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

pub const Typ = union(enum) {
    pub const Array = struct {
        len: []const u8,
        typ: Typ,
    };

    prime: Prime,
    name: []const u8,
    ptr: *const Typ,
    array: *const Array,

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
    u32,
    u64,
    bool,
    void,

    pub fn isNumber(prime: Prime) bool {
        switch (prime) {
            .i32, .u8, .u32, .u64 => return true,
            .bool, .void => return false,
        }
    }
};

const Block = []const Statement;

pub const Fun = struct {
    header: Header,
    body: Block,
};

pub const Statement = union(enum) {
    brek: Break,
    ret: Return,
    expr: Expr,
    declare: Declare,
    assign: Assign,
    iff: If,
    whi: While,
    ignore: Expr,
    mut_declare: Declare,
};

pub const Return = struct {
    expr: Expr,
};

pub const Break = struct {
    location: Location,
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
    left: Expr,
    expr: Expr,
    location: Location,
};

pub const Declare = struct {
    name: []const u8,
    typ: ?Typ,
    expr: Expr,
    location: Location,
};

pub const Call = struct {
    name: []const u8,
    args: []const Expr,
    location: Location,
};

pub const Ptr = struct {
    expr: Expr,
    location: Location,
};

pub const Notb = struct {
    expr: Expr,
    location: Location,
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
    location: Location,
};

pub const Expr = union(enum) {
    lit_loc: LitLoc,
    call: Call,
    binary: *const Binary,
    field: *const Field,
    struc: StructExpr,
    ptr: *const Ptr,
    notb: *const Notb,
    elem: *const Elem,

    pub fn location(expr: Expr) Location {
        switch (expr) {
            .elem => |elem| return elem.location,
            .lit_loc => |lit_loc| return lit_loc.location,
            .call => |call| return call.location,
            .binary => |binary| return binary.location,
            .field => |field| return field.location,
            .struc => |struc| return struc.location,
            .ptr => |ptr| return ptr.location,
            .notb => |notb| return notb.location,
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

pub const LitLoc = struct {
    literal: Literal,
    location: Location,
};

pub const Literal = union(enum) {
    int: []const u8,
    str: usize,
    vari: []const u8,
    char: u8,
    undef: Undef,
    bool: bool,
};

pub const Undef = struct {
    typ_id: usize,
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
    orb,
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
            .orb => return 1,
            .andb => return 2,
            .add, .sub => return 3,
            .mul, .div, .rem => return 4,
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

pub const Info = struct {
    typ_ids: usize,
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
