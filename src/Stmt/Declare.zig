const std = @import("std");

const okc = @import("okc");

typ: ?okc.Typ,
expr: okc.Expr,
mutable: bool,

const Declare = @This();

pub const Named = struct {
    name: []const u8,
    bare: Declare,

    pub fn check(self: *@This(), location: okc.Location, ctx: *okc.Stmt.Check) !okc.ControlFlow {
        const typ_decl = if (self.bare.typ) |typ| typ else .any;
        const info = try self.bare.expr.check(.{ .typ = typ_decl }, ctx.exprCheck());
        const typ = info.typ.unify(typ_decl, self.bare.expr.location, ctx.failer);
        try ctx.declare(self.name, location, .{
            .typ = typ,
            .mutable = self.bare.mutable,
            .can_be_mutable = true,
        }, ctx.failer);
        return .cont;
    }
};

pub const Info = struct {
    typ: okc.Typ,
    can_be_mutable: bool,
    mutable: bool,
    mutated: bool = false,

    pub fn checkUsage(self: @This(), location: okc.Location, failer: *okc.Failer) void {
        if (self.mutable and !self.mutated) {
            failer.fail(location, "variable is never mutated", .{});
            std.log.info("remove `mut` before name\n", .{});
        }
    }
};
