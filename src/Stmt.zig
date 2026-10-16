const Checker = @import("Checker.zig");
const Expr = @import("Expr/Expr.zig");
const Failer = @import("Failer.zig");
const Item = @import("Item.zig");
const Location = @import("Location.zig");
const Typ = @import("typ/typ.zig").Typ;

location: Location,
kind: Kind,

pub const Kind = union(enum) {
    assign: Assign,
    brek,
    declare: Item.Declare.Named,
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

const Stmt = @This();

pub const For = struct {
    vari: []const u8,
    expr: Expr,
    body: []Stmt,
    vari_location: Location,
};

pub const ForRange = struct {
    vari: []const u8,
    start: Expr,
    end: Expr,
    body: []Stmt,
    vari_location: Location,
};

pub const Ignore = struct {
    expr: Expr,
};

pub const Return = struct {
    expr: ?Expr,

    pub fn check(
        ret: *@This(),
        location: Location,
        ret_typ: Typ,
        failer: *Failer,
        checker: *Checker,
    ) !ControlFlow {
        if (ret.expr) |*expr| {
            const info = try checker.checkExpr(expr, .{ .typ = ret_typ });
            _ = checker.unify(expr.location, ret_typ, info.typ);
        } else if (!ret_typ.isVoid()) {
            failer.fail(location, "should return a value", .{});
        }
        return .ret;
    }
};

pub const While = struct {
    branch: Branch,
};

pub const IfStmt = struct {
    branch: Branch,
    else_ifs: []Branch,
    else_branch: []Stmt,
};

pub const Branch = struct {
    condition: Expr,
    body: []Stmt,

    pub const Kind = enum {
        loop,
        simple,
    };
};

pub const Assign = struct {
    left: Expr,
    expr: Expr,
};

pub const OpAssign = struct {
    left: Expr,
    kind: Expr.Binary.Kind,
    right: Expr,
};

// numbered to enable `<`
pub const ControlFlow = enum(u2) {
    cont = 0,
    brek = 1,
    ret = 2,
};
