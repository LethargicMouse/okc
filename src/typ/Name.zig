const std = @import("std");

const okc = @import("okc");

name: []const u8,
generics: []const okc.Typ = &.{},

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

    pub fn checkDecl(self: @This(), items: std.StringHashMap(okc.Item.Info), failer: *okc.Failer) error{BadType}!?okc.Typ {
        std.log.debug("checkTypDecl {f}", .{self.bare});
        const item = items.getPtr(self.bare.name) orelse {
            failer.fail(self.location, "item `{s}` is not declared", .{self.bare.name});
            return error.BadType;
        };
        switch (item.kind) {
            .module => unreachable,
            .fun, .vari => {
                failer.fail(self.location, "item `{s}` is not a type", .{self.bare.name});
                return error.BadType;
            },
            .typ => |typ| {
                item.used = true;
                return typ;
            },
            .struc => |struc| {
                item.used = true;
                std.log.debug("item {s} used", .{self.bare.name});
                if (struc.generics.len != self.bare.generics.len) {
                    failer.fail(
                        self.location,
                        "expected {} generics\n        found {}",
                        .{ struc.generics.len, self.bare.generics.len },
                    );
                }
                return null;
            },
        }
    }
};
