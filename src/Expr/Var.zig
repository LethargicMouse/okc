const std = @import("std");

const okc = @import("okc");

name: []const u8,
kind: Kind = .simple,

pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !@This() {
    const name = try ctx.parseName(mode);
    return .{ .name = name };
}

pub fn genRefIn(self: @This(), typ: okc.Typ.Name, ctx: *okc.Codegen) !okc.Val.Ref {
    const item = ctx.module.items.get(typ.name).?;
    switch (item) {
        .typ_decl => |decl| {
            try decl.gen(typ, ctx);
            const index = ctx.typ_decls.get(typ).?
                .variants.get(self.name).?;
            var res: okc.Val.Typed = .{
                .typ = .{ .name = typ },
                .bare = .undef,
            };
            try ctx.genIV(&res, .{
                .typ = .{ .prime = .i32 },
                .bare = .{ .int = index },
            }, 0);
            return ctx.toStack(res);
        },
        .use => {
            const old = ctx.module;
            defer ctx.module = old;
            ctx.module = try .get(typ.name, ctx);
            return self.genRef(ctx);
        },
        else => unreachable,
    }
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    switch (self.kind) {
        .fun => |fun| return ctx.toStack(try fun.gen(self.name, ctx)),
        .typ => return .{
            .inner_typ = .typ,
            .val = .undef,
        },
        .simple => {
            std.log.debug("var ref `{s}`", .{self.name});
            return ctx.vars.get(self.name) orelse {
                try okc.Item.Const.genNamed(self.name, ctx);
                return .{
                    .inner_typ = ctx.consts.get(self.name).?,
                    .val = .{ .global = .{ .name = self.name } },
                };
            };
        },
    }
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    switch (self.kind) {
        .fun => |fun| return fun.gen(self.name, ctx),
        .typ => return .{
            .typ = .typ,
            .bare = .undef,
        },
        .simple => {
            const ref = try self.genRef(ctx);
            return ref.loadTypVal(ctx.loadCtx());
        },
    }
}

pub fn checkIn(
    self: *@This(),
    typ: okc.Typ.Name,
    location: okc.Location,
    mutability: Mutability,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    const item = ctx.items.getPtr(typ.name).?;
    item.used = true;
    const decl = item.getTypDecl(typ, ctx) orelse {
        ctx.failer.noMember(location, self.name, .{ .name = typ });
        return .{
            .typ = .err,
            .mutable = true,
        };
    };
    if (decl.variants.getPtr(self.name)) |variant| {
        variant.used = true;
        return .{
            .typ = .{ .name = typ },
            .mutable = false,
        };
    } else {
        const inner_ctx = ctx.inside(.{ .name = typ }) orelse {
            ctx.failer.noMember(location, self.name, .{ .name = typ });
            return .{
                .typ = .err,
                .mutable = true,
            };
        };
        return self.check(location, mutability, inner_ctx);
    }
}

pub fn check(
    self: *@This(),
    location: okc.Location,
    mutability: Mutability,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    const err = okc.Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    const item = ctx.items.getPtr(self.name) orelse {
        ctx.failer.notDeclared(location, self.name);
        return err;
    };
    switch (item.kind) {
        .fun => |header| {
            item.used = true;
            self.kind = .{ .fun = undefined };
            return self.kind.fun.fillFromHeader(ctx.gpa, ctx.arena, header.*);
        },
        .typ_decl, .alias, .module => {
            self.kind = .typ;
            return .{
                .typ = .typ,
                .mutable = false,
            };
        },
        .vari => |*vari_decl| {
            item.used = true;
            if (mutability == .mutable) {
                if (vari_decl.mutable) {
                    vari_decl.mutated = true;
                } else {
                    if (vari_decl.can_be_mutable) {
                        std.log.info("add `mut` before name in {f}", .{item.location});
                    }
                }
            }
            return .{
                .typ = vari_decl.typ,
                .mutable = vari_decl.mutable,
            };
        },
    }
}

pub const Kind = union(enum) {
    fun: okc.Expr.FunMeta,
    simple,
    typ,
};

pub const Mutability = enum {
    constant,
    mutable,
};
