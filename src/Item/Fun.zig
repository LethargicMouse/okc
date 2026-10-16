const okc = @import("okc");

header: Header,
body: okc.Stmt.Block,

pub fn check(self: @This(), location: okc.Location, ctx: okc.Item.Check) !void {
    var stmt_check: okc.Stmt.Check = ctx.checkStmt(self.header.ret_typ);
    defer stmt_check.deinit();
    for (self.header.params) |param| {
        try stmt_check.declare(param.name, param.location, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        }, ctx.failer);
    }
    const control_flow = try self.body.check(&stmt_check);
    if (control_flow != .ret and !self.header.ret_typ.isVoid()) {
        ctx.failer.fail(location, "function may not return", .{});
    }
    stmt_check.freeVars(0);
}

pub const Extern = struct {
    header: Header,
};

pub const Header = struct {
    generics: []const okc.Item.Generic,
    params: []Param,
    ret_typ: okc.Typ,

    pub fn check(self: *@This(), ctx: okc.Item.Check) !void {
        var generics_checker: okc.Item.Generic.Checker = try .init(ctx.gpa, self.generics);
        defer generics_checker.deinit(ctx.gpa);
        const typ_check = ctx.checkTyp(&generics_checker);
        for (self.params) |*param| {
            param.typ = try param.typ.check(typ_check);
        }
        self.ret_typ = try self.ret_typ.check(typ_check);
        generics_checker.checkUsage(ctx.failer);
    }

    pub const Param = struct {
        name: []const u8,
        typ: okc.Typ,
        location: okc.Location,
    };
};
