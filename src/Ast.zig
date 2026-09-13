const std = @import("std");

const builtin = @import("builtin");
const Lexeme = @import("Lexer.zig").Lexeme;
pub const Typs = @import("AstTyps.zig");
pub const Typ = Typs.Typ;

const Location = @import("Location.zig");

pub const ExtFun = struct {
    header: Header,
};

pub const Header = struct {
    name: []const u8,
    generics: []const []const u8,
    params: []const Param,
    ret_typ: Typ,
};

pub const Param = struct {
    name: []const u8,
    typ: Typ,
    location: Location,
};

pub const Fun = struct {
    header: Header,
    body: []Statement,
};

pub const OpAssign = struct {
    left: Expr,
    kind: Binary.Kind,
    right: Expr,
};

pub const Statement = struct {
    pub const Kind = union(enum) {
        ret: Return,
        expr: Expr,
        declare: Declare,
        assign: Assign,
        op_assign: OpAssign,
        iff: If,
        whi: While,
        ignore: Ignore,
        mut_declare: Declare,
        brek,
        unre,
    };
    location: Location,
    kind: Kind,
};

pub const Ignore = struct {
    expr: Expr,
};

pub const Return = struct {
    expr: ?Expr,
};

pub const While = struct {
    branch: Branch,
};

pub const If = struct {
    branch: Branch,
    else_ifs: []Branch,
    else_branch: []Statement,
};

pub const Branch = struct {
    condition: Expr,
    body: []Statement,
};

pub const Assign = struct {
    left: Expr,
    expr: Expr,
};

pub const Declare = struct {
    name: []const u8,
    typ: ?Typ,
    expr: Expr,
};

pub const Call = struct {
    name: []const u8,
    args: []Expr,
    generics: []Typ = undefined,
    ret_typ: Typ = undefined,
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
};

pub const Unary = struct {
    pub const Kind = enum {
        ptr,
        deref,
        notb,
    };
    kind: Kind,
    expr: Expr,
};

pub const Int = struct {
    val: u64,
    typ: Typ = undefined,
};

pub const Array = struct {
    exprs: []Expr,
    typ: Typ = undefined,
};

pub const Expr = struct {
    pub const Kind = union(enum) {
        array: Array,
        unary: *Unary,
        infer_struc: InferStruct,
        int: Int,
        str: usize,
        vari: []const u8,
        char: u8,
        undef: Undef,
        bool: bool,
        call: Call,
        binary: *Binary,
        field: *Field,
        struc: StructExpr,
        elem: *Elem,
    };
    location: Location,
    kind: Kind,
};

pub const StructExpr = struct {
    name: []const u8,
    fields: []NewField,
    typ: Typ = undefined,
};

pub const InferStruct = struct {
    fields: []NewField,
    typ: Typ = undefined,
};

pub const NewField = struct {
    name: []const u8,
    expr: Expr,
    location: Location,
};

// lol
pub const Undef = struct {
    typ: *Typ,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
    typ: *Typ,
};

pub const Binary = struct {
    pub const Kind = enum {
        pub const Class = enum {
            arith,
            bool,
        };

        orb,
        andb,
        equ,
        add,
        sub,
        mul,
        div,
        les,
        rem,
        moreq,

        pub fn getPrior(kind: Kind) u8 {
            switch (kind) {
                .equ, .les, .moreq => return 0,
                .orb => return 1,
                .andb => return 2,
                .add, .sub => return 3,
                .mul, .div, .rem => return 4,
            }
        }

        pub fn fromLexeme(lexeme: Lexeme) ?Kind {
            return switch (lexeme) {
                .pipe => .orb,
                .amp => .andb,
                .equ2 => .equ,
                .plus => .add,
                .minus => .sub,
                .star => .mul,
                .slash => .div,
                .les => .les,
                .rem => .rem,
                .moreq => .moreq,
                else => null,
            };
        }

        pub fn getClass(kind: Kind) Class {
            return switch (kind) {
                .orb, .andb, .add, .sub, .mul, .div, .rem => .arith,
                .equ, .les, .moreq => .bool,
            };
        }
    };

    left: Expr,
    kind: Kind,
    right: Expr,
};

pub const Struct = struct {
    name: []const u8,
    generics: []const []const u8,
    fields: []const FieldDecl,
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: Typ,
    location: Location,
};

pub const Item = struct {
    pub const Kind = union(enum) {
        ext_fun: ExtFun,
        struc: Struct,
        fun: Fun,
        constant: Declare,
    };

    kind: Kind,
    location: Location,
};

const Ast = @This();

typs: Typs,
items: []Item,
strs: []const []const u8,
location: Location,

pub fn deinit(ast: *Ast) void {
    ast.typs.deinit();
    ast.* = undefined;
}
