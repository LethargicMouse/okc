const std = @import("std");

const okc = @import("okc");

declare: okc.Stmt.Declare,

pub fn genNamed(name: []const u8, ctx: *okc.Codegen) !void {
    const was = try ctx.generated.getOrPut(.{ .name = name });
    if (was.found_existing) {
        return;
    }
    std.log.debug("gen const `{s}`", .{name});
    const expr = ctx.module.items.get(name).?.constant.declare.expr;
    const buffer = ctx.buffer.?;
    ctx.buffer = .empty;
    defer {
        ctx.buffer.?.deinit(ctx.gpa);
        ctx.buffer = buffer;
    }
    try ctx.buffer.?.print(ctx.gpa, "\n@{s} = private unnamed_addr constant ", .{name});
    const typ = try expr.genConst(ctx);
    try ctx.consts.put(name, typ);
    try ctx.writer.interface.writeAll(ctx.buffer.?.items);
}

pub fn reg(self: *@This(), ctx: okc.Item.Check) !okc.Stmt.Declare.Info {
    const hint_typ = if (self.declare.typ) |typ| typ else .any;
    const typ = try self.declare.expr.checkConst(.{ .typ = hint_typ }, ctx.checkExprCtx());
    if (self.declare.typ) |typ_decl| {
        _ = typ.unify(typ_decl, self.declare.expr.location, ctx.failer);
    }
    return .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    };
}
