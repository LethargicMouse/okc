const std = @import("std");
const builtin = @import("builtin");

pub const Expr = @import("Ast/Expr.zig");
pub const Typ = @import("Ast/typ.zig").Typ;
const Lexeme = @import("Lexer.zig").Lexeme;
const Location = @import("Location.zig");

pub const ExtFun = struct {
    header: Header,
};

pub const Header = struct {
    name: []const u8,
    generics: []const Generic,
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
    kind: Expr.Binary.Kind,
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

pub const GlobalVar = struct {
    name: []const u8,
    typ: Typ,
};

pub const Generic = struct {
    name: []const u8,
    location: Location,
};

pub const Struct = struct {
    name: []const u8,
    generics: []const Generic,
    fields: []FieldDecl,
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: Typ,
    default: ?Expr,
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

    pub fn getName(item: Item) []const u8 {
        return switch (item.kind) {
            .ext_fun => |ext_fun| ext_fun.header.name,
            .struc => |struc| struc.name,
            .fun => |fun| fun.header.name,
            .constant => |declare| declare.name,
        };
    }

    pub fn getHeader(item: Item) ?Header {
        return switch (item.kind) {
            .ext_fun => |ext_fun| ext_fun.header,
            .fun => |fun| fun.header,
            .constant, .struc => null,
        };
    }
};

const Ast = @This();

items: []Item,
location: Location,
