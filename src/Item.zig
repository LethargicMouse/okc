const okc = @import("okc");

pub const Check = @import("Item/Check.zig");
pub const Const = @import("Item/Const.zig");
pub const Fun = @import("Item/Fun.zig");
pub const Generic = @import("Item/Generic.zig");
pub const Info = @import("Item/Info.zig");
pub const Struct = @import("Item/Struct.zig");

name: []const u8,
kind: Kind,
location: okc.Location,

pub fn reg(self: *@This(), ctx: Check) !void {
    const kind: okc.Item.Info.Kind = switch (self.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .struc => |struc| .{ .struc = try struc.reg(ctx) },
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*constt| try constt.reg(ctx),
        .use => unreachable,
    };
    if (kind == .fun) {
        try kind.fun.check(ctx);
    }
    if (ctx.items.get(self.name)) |prev| {
        ctx.failer.alreadyDeclared(self.location, self.name, prev.location);
        return;
    }
    try ctx.items.put(self.name, .{
        .location = self.location,
        .kind = kind,
    });
}

pub fn check(self: @This(), ctx: Check) error{OutOfMemory}!void {
    switch (self.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try fun.check(self.location, ctx),
        .use => unreachable,
    }
}

pub const Kind = union(enum) {
    constant: Const,
    ext_fun: okc.Item.Fun.Extern,
    fun: Fun,
    struc: Struct,
    typ_alias: TypAlias,
    use,
};

pub const TypAlias = struct {
    typ: okc.Typ,
};
