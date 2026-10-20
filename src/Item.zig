const std = @import("std");

const okc = @import("okc");

pub const Check = @import("Item/Check.zig");
pub const Const = @import("Item/Const.zig");
pub const Fun = @import("Item/Fun.zig");
pub const Generic = @import("Item/Generic.zig");
pub const Info = @import("Item/Info.zig");
pub const Typ = @import("Item/Typ.zig");

name: []const u8,
kind: Kind,
location: okc.Location,

pub fn reg(self: *@This(), ctx: Check) !void {
    const kind: okc.Item.Info.Kind = switch (self.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .typ => |struc| .{ .struc = try struc.reg(ctx) },
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*constt| .{ .vari = try constt.reg(ctx) },
        .use => .{ .module = try .load(self.name, self.location, ctx.loadCtx()) },
    };
    if (kind == .fun) {
        try kind.fun.check(ctx);
    }
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
        .typ_alias, .constant, .typ, .ext_fun, .use => {},
        .fun => |fun| try fun.check(self.location, ctx),
    }
}

pub const Kind = union(enum) {
    constant: Const,
    ext_fun: okc.Item.Fun.Extern,
    fun: Fun,
    typ: Typ,
    typ_alias: TypAlias,
    use,

    pub fn getStruct(self: @This(), name: []const u8, ctx: *okc.Codegen) !Typ {
        switch (self) {
            .typ => |struc| return struc,
            .use => {
                const module = try ctx.getModule(name);
                return module.items.get("Self").?.typ;
            },
            else => unreachable,
        }
    }
};

pub const TypAlias = struct {
    typ: okc.Typ,
};
