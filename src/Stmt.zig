const okc = @import("okc");

pub const Assign = @import("Stmt/Assign.zig");
pub const Block = @import("Stmt/Block.zig");
pub const Branch = @import("Stmt/Branch.zig");
pub const brek = @import("Stmt/brek.zig");
pub const Check = @import("Stmt/Check.zig");
pub const Declare = @import("Stmt/Declare.zig");
pub const Expr = @import("Stmt/Expr.zig");
pub const For = @import("Stmt/For.zig");
pub const ForRange = @import("Stmt/ForRange.zig");
pub const IfStmt = @import("Stmt/IfStmt.zig");
pub const Ignore = @import("Stmt/Ignore.zig");
pub const OpAssign = @import("Stmt/OpAssign.zig");
pub const Return = @import("Stmt/Return.zig");
pub const Switch = @import("Stmt/Switch.zig");
pub const While = @import("Stmt/While.zig");

location: okc.Location,
kind: Kind,

pub fn parse(ctx: *okc.Parser) !@This() {
    return ctx.either(.{
        Switch.parseStmt,
        okc.Parser.parseUnreachableStmt,
        okc.Parser.parseBreakStmt,
        okc.Parser.parseRetStmt,
        okc.Parser.parseDeclareStmt,
        okc.Parser.parseIfStmt,
        okc.Parser.parseForStmt,
        okc.Parser.parseWhileStmt,
        okc.Parser.parseIgnoreStmt,
        okc.Parser.parseExprStmt,
    }) catch |err| {
        try ctx.fail("<statement>");
        return err;
    };
}

pub fn check(self: *@This(), ctx: *Check) error{OutOfMemory}!okc.ControlFlow {
    switch (self.kind) {
        .swi => unreachable,
        .for_range => |*forr| return forr.check(ctx),
        .forr => |*forr| return forr.check(ctx),
        .unre => return .ret,
        .brek => return brek.check(self.location, ctx.*),
        .ret => |*ret| return ret.check(self.location, ctx.ret_typ, ctx.exprCheck()),
        .expr => |*expr| return Expr.check(expr, ctx.exprCheck()),
        .declare => |*named| return named.check(self.location, ctx),
        .op_assign => |*op_assign| return op_assign.check(ctx.exprCheck()),
        .assign => |*assign| return assign.check(ctx.exprCheck()),
        .iff => |*iff| return iff.check(ctx),
        .whi => |*whi| return whi.check(ctx),
        .ignore => |*ignore| return ignore.check(self.location, ctx.exprCheck()),
    }
}

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
    swi: Switch,
    unre,
    whi: While,
};
