const Location = @import("../Location.zig");
const Typ = @import("../typ/mod.zig").Typ;
const Expr = @import("../Expr/Expr.zig");

const Self = @This();
location: Location,
kind: Kind,

pub const Kind = union(enum) {
    assign: Assign,
    brek,
    declare: Declare.Named,
    expr: Expr,
    for_range: ForRange,
    forr: For,
    iff: IfStmt,
    ignore: Ignore,
    op_assign: OpAssign,
    ret: Return,
    unre,
    whi: While,
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

pub const IfStmt = struct {
    branch: Branch,
    else_ifs: []Branch,
    else_branch: []Self,
};

pub const Branch = struct {
    condition: Expr,
    body: []Self,

    pub const Kind = enum {
        loop,
        simple,
    };
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
