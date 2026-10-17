const std = @import("std");

const okc = @import("okc");

name: []const u8,
fun_meta: ?okc.Expr.FunMeta = null,

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    if (self.fun_meta) |fun_meta| {
        return ctx.toStack(try ctx.genFunPtr(self.name, fun_meta));
    }
    return ctx.vars.get(self.name) orelse {
        try ctx.genConst(self.name);
        return .{
            .inner_typ = ctx.consts.get(self.name).?,
            .val = .{ .global = .{ .name = self.name } },
        };
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    if (self.fun_meta) |fun_meta| {
        return ctx.genFunPtr(self.name, fun_meta);
    }
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx.loadCtx());
}

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint_mutable: bool,
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
        .module => unreachable,
        .fun => |header| {
            item.used = true;
            self.fun_meta = @as(okc.Expr.FunMeta, undefined);
            return self.fun_meta.?.fillFromHeader(ctx.gpa, ctx.arena, header.*);
        },
        .struc, .typ => {
            ctx.failer.fail(location, "it is a type", .{});
            return err;
        },
        .vari => |*vari_decl| {
            item.used = true;
            if (hint_mutable) {
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
