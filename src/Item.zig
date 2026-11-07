const std = @import("std");

const okc = @import("okc");

pub const Check = @import("Item/Check.zig");
pub const Const = @import("Item/Const.zig");
pub const Fun = @import("Item/Fun.zig");
pub const Generic = @import("Item/Generic.zig");
pub const Info = @import("Item/Info.zig");
pub const TypAlias = @import("Item/TypAlias.zig");
pub const TypDecl = @import("Item/TypDecl.zig");

name: []const u8,
kind: Kind,
location: okc.Location,

pub fn parseGenerics(ctx: *okc.Parser) ![]const okc.Item.Generic {
    try ctx.expect(.les, .quiet);
    const res = try ctx.sep(okc.Item.Generic.parse, .{});
    try ctx.expect(.mor, .loud);
    return res;
}

fn parseUsePath(ctx: *okc.Parser) ![]const u8 {
    const name = try ctx.parseName(.quiet);
    try ctx.expect(.dot, .quiet);
    return name;
}

fn parseUse(ctx: *okc.Parser) !@This() {
    try ctx.expect(.use, .quiet);
    const path = try ctx.many(parseUsePath, .{});
    const location = ctx.getLocation();
    const name = try ctx.parseName(.loud);
    try ctx.expect(.semi, .loud);
    return .{
        .location = location,
        .name = name,
        .kind = .{ .use = path },
    };
}

pub fn parse(ctx: *okc.Parser) error{ OutOfMemory, ParseFailed }!@This() {
    return ctx.either(.{
        Fun.parseItem,
        TypDecl.parseItem,
        Fun.Extern.parseItem,
        Const.parseItem,
        TypAlias.parseItem,
        parseUse,
    }) catch |err| {
        try ctx.fail("<item>");
        return err;
    };
}

pub fn reg(self: *@This(), ctx: Check) !void {
    const kind: okc.Item.Info.Kind = switch (self.kind) {
        .typ_alias => |alias| .{ .alias = alias },
        .ext_fun => |*ext_fun| .{ .fun = try ext_fun.header.makeInfo(ctx) },
        .typ_decl => |typ| .{ .typ_decl = try typ.makeInfo(ctx) },
        .fun => |*fun| .{ .fun = try fun.header.makeInfo(ctx) },
        .constant => |*constt| .{ .vari = try constt.reg(ctx) },
        .use => |path| .{ .module = try .load(path, self.name, self.location, ctx.loadCtx()) },
    };
    const name = if (std.mem.eql(u8, self.name, "Self"))
        ctx.mod_typ.name
    else
        self.name;
    if (ctx.items.get(name)) |prev| {
        ctx.failer.alreadyDeclared(self.location, self.name, prev.location);
        return;
    }
    try ctx.items.put(name, .{
        .location = self.location,
        .kind = kind,
    });
}

pub fn check(self: @This(), ctx: Check) error{OutOfMemory}!void {
    switch (self.kind) {
        .typ_alias, .constant, .typ_decl, .ext_fun, .use => {},
        .fun => |fun| try fun.check(
            self.location,
            ctx.items.get(self.name).?.kind.fun.generics_usage,
            ctx,
        ),
    }
}

pub const Kind = union(enum) {
    constant: Const,
    ext_fun: okc.Item.Fun.Extern,
    fun: Fun,
    typ_alias: TypAlias,
    typ_decl: TypDecl,
    use: []const []const u8,
};
