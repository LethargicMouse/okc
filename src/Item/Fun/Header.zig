const std = @import("std");

const okc = @import("okc");

generics: []const okc.Item.Generic,
params: []okc.Item.Fun.Param,
context: []okc.Item.Fun.Param,
ret_typ: okc.Typ,

pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !okc.Item.Fun.Header {
    try ctx.expect(.fun, mode);
    ctx.tmp_location = ctx.getLocation();
    ctx.tmp_name = try ctx.parseName(.loud);
    const generics = try ctx.maybe(okc.Item.parseGenerics, .{}) orelse &.{};
    try ctx.expect(.parl, .loud);
    const params = try ctx.sep(okc.Item.Fun.Param.parse, .{});
    try ctx.expect(.parr, .loud);
    const context = try ctx.maybe(parseContext, .{}) orelse @constCast(&.{});
    const ret_typ: okc.Typ = try .parse(ctx);
    return .{
        .generics = generics,
        .params = params,
        .context = context,
        .ret_typ = ret_typ,
    };
}

pub fn parseContext(ctx: *okc.Parser) ![]okc.Item.Fun.Param {
    try ctx.expect(.ctx, .quiet);
    try ctx.expect(.curl, .loud);
    const params = try ctx.sep(okc.Item.Fun.Param.parse, .{});
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    const endmode: okc.Parser.Mode = if (prev == .comma or prev == .curl) .quiet else .loud;
    try ctx.expect(.curr, endmode);
    return params;
}

pub fn makeInfo(self: *@This(), ctx: okc.Item.Check) !Info {
    // for typ `vars` functionality
    var stmt_ctx = ctx.stmtCheckCtx(self.*);
    defer stmt_ctx.deinit();
    try self.regGenerics(null, &stmt_ctx);
    const typ_check_ctx = ctx.typCheckCtx();
    for (self.params) |*param| {
        param.typ = try param.typ.check(typ_check_ctx);
    }
    for (self.context) |*param| {
        param.typ = try param.typ.check(typ_check_ctx);
    }
    self.ret_typ = try self.ret_typ.check(typ_check_ctx);
    var generics_usage: std.bit_set.Dynamic = try .initEmpty(ctx.gpa, self.generics.len);
    for (self.generics, 0..) |generic, i| {
        generics_usage.setValue(i, ctx.items.get(generic.name).?.used);
    }
    stmt_ctx.freeVars(0);
    return .{
        .generics_usage = generics_usage,
        .header = self.*,
    };
}

pub fn regGenerics(self: @This(), musage: ?std.bit_set.Dynamic, ctx: *okc.Stmt.Check) !void {
    for (self.generics, 0..) |generic, i| {
        try ctx.declare(generic.name, generic.location, .{
            .typ = .typ,
            .can_be_mutable = false,
            .mutable = false,
        });
        if (musage) |usage| {
            ctx.items.getPtr(generic.name).?.used = usage.isSet(i);
        }
    }
}

const Header = @This();

pub const Info = struct {
    header: Header,
    generics_usage: std.bit_set.Dynamic,

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.generics_usage.deinit(gpa);
        self.* = undefined;
    }
};
