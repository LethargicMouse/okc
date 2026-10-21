const std = @import("std");

const okc = @import("okc");

name: []const u8,
generics: []const okc.Typ = &.{},

pub fn getItems(self: @This(), items: std.StringHashMap(okc.Item.Info)) ?std.StringHashMap(okc.Item.Info) {
    const item = items.get(self.name).?;
    switch (item.kind) {
        .module => |mod| return mod.items,
        else => return null,
    }
}

pub fn updateGenerics(
    self: @This(),
    fun: anytype,
    args: anytype,
    arena: std.mem.Allocator,
) !@This() {
    const generics = try arena.alloc(okc.Typ, self.generics.len);
    defer arena.free(generics);
    for (generics, self.generics) |*target, generic| {
        target.* = try @call(.auto, fun, .{generic} ++ args);
    }
    return .{
        .name = self.name,
        .generics = try okc.Typ.memo.save(generics, arena),
    };
}

pub fn eql(a: @This(), b: @This()) bool {
    if (!std.mem.eql(u8, a.name, b.name)) {
        return false;
    }
    for (a.generics, b.generics) |atyp, btyp| {
        if (!atyp.eql(btyp)) {
            return false;
        }
    }
    return true;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(self.name);
    // `self.name` determines number of `self.generics`
    for (self.generics) |gen| {
        gen.hashIn(hasher);
    }
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll(self.name);
    if (self.generics.len != 0) {
        try writer.print("<{f}", .{self.generics[0]});
        for (self.generics[1..]) |generic| {
            try writer.print(", {f}", .{generic});
        }
        try writer.writeByte('>');
    }
}

const Name = @This();

pub const Located = struct {
    bare: Name,
    location: okc.Location,

    pub fn checkDecl(self: @This(), ctx: okc.Typ.Check) error{BadType}!?okc.Typ {
        std.log.debug("checkTypDecl {f}", .{self.bare});
        const name = if (std.mem.eql(u8, self.bare.name, "Self"))
            ctx.mod_typ.name
        else
            self.bare.name;
        const item = ctx.items.getPtr(name) orelse {
            ctx.failer.fail(self.location, "item `{s}` is not declared", .{self.bare.name});
            return error.BadType;
        };
        switch (item.kind) {
            .module => unreachable,
            .fun, .vari => {
                ctx.failer.fail(self.location, "item `{s}` is not a type", .{self.bare.name});
                return error.BadType;
            },
            .alias => |alias| {
                item.used = true;
                return alias.typ;
            },
            .typ => |typ| {
                item.used = true;
                std.log.debug("item {s} used", .{name});
                if (typ.generics.len != self.bare.generics.len) {
                    ctx.failer.fail(
                        self.location,
                        "expected {} generics\n        found {}",
                        .{ typ.generics.len, self.bare.generics.len },
                    );
                }
                if (std.mem.eql(u8, self.bare.name, "Self")) {
                    return .{ .name = ctx.mod_typ };
                } else {
                    return null;
                }
            },
        }
    }
};
