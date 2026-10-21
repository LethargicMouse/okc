const std = @import("std");

const okc = @import("okc");

name: []const u8,
kind: Kind = .simple,

pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !@This() {
    const name = try ctx.parseName(mode);
    return .{ .name = name };
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    switch (self.kind) {
        .fun => |fun| return ctx.toStack(try ctx.genFunPtr(self.name, fun)),
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
        .fun => |fun| return ctx.genFunPtr(self.name, fun),
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

pub fn check(
    self: *@This(),
    location: okc.Location,
    mutability: enum { constant, mutable },
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
        .typ, .alias, .module => {
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
