const Location = @import("../Location.zig");
const Expr = @import("Expr/mod.zig");
const Typ = @import("../typ/mod.zig").Typ;

const Self = @This();
location: Location,
kind: Kind,

pub const Kind = union(enum) {
    forr: For,
    for_range: ForRange,
    ret: Return,
    expr: Expr,
    declare: Declare.Named,
    assign: Assign,
    op_assign: OpAssign,
    iff: If,
    whi: While,
    ignore: Ignore,
    brek,
    unre,
};

pub const For = struct {
    vari: []const u8,
    expr: Expr,
    body: []Self,
    vari_location: Location,
};

pub const ForRange = struct {
    vari: []const u8,
    start: Expr,
    end: Expr,
    body: []Self,
    vari_location: Location,
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
    else_branch: []Self,
};

pub const Branch = struct {
    condition: Expr,
    body: []Self,
};

pub const Assign = struct {
    left: Expr,
    expr: Expr,
};

pub const Declare = struct {
    typ: ?Typ,
    expr: Expr,
    mutable: bool,

    pub const Named = struct {
        name: []const u8,
        declare: Declare,
    };
};

pub const OpAssign = struct {
    left: Expr,
    kind: Expr.Binary.Kind,
    right: Expr,
};
