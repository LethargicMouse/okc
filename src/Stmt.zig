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
pub const unre = @import("Stmt/unre.zig");
pub const While = @import("Stmt/While.zig");

location: okc.Location,
kind: Kind,

pub fn gen(self: @This(), ctx: *okc.Codegen) error{ WriteFailed, OutOfMemory }!void {
    switch (self.kind) {
        .swi => |swi| try swi.gen(ctx),
        .for_range => |forr| try forr.gen(ctx),
        .forr => |forr| try forr.gen(ctx),
        .op_assign => |op_assign| try op_assign.gen(ctx),
        .unre => try unre.gen(ctx),
        .ret => |ret| try ret.gen(ctx),
        .expr => |expr| _ = try expr.expr.gen(ctx),
        .declare => |declare| try declare.gen(ctx),
        .assign => |assign| try assign.gen(ctx),
        .iff => |iff| try iff.gen(ctx),
        .whi => |whi| try whi.gen(ctx),
        .ignore => |ignore| _ = try ignore.expr.gen(ctx),
        .brek => try brek.gen(ctx),
    }
}

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
    return switch (self.kind) {
        .swi => |*swi| swi.check(ctx),
        .for_range => |*forr| forr.check(ctx),
        .forr => |*forr| forr.check(ctx),
        .unre => .ret,
        .brek => brek.check(self.location, ctx.*),
        .ret => |*ret| ret.check(self.location, ctx.ret_typ, ctx.exprCheckCtx()),
        .expr => |*expr| Expr.check(expr, ctx.exprCheckCtx()),
        .declare => |*named| named.check(self.location, ctx),
        .op_assign => |*op_assign| op_assign.check(ctx.exprCheckCtx()),
        .assign => |*assign| assign.check(ctx.exprCheckCtx()),
        .iff => |*iff| iff.check(ctx),
        .whi => |*whi| whi.check(ctx),
        .ignore => |*ignore| ignore.check(self.location, ctx.exprCheckCtx()),
    };
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
