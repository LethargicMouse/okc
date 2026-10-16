const std = @import("std");

const Failer = @import("../Failer.zig");
const Item = @import("../Item.zig");
const Location = @import("../Location.zig");
const Module = @import("../Module.zig");
const Typ = @import("typ.zig").Typ;

name: []const u8,
generics: []const Typ = &.{},

pub fn updateGenerics(self: @This(), fun: anytype, args: anytype) !@This() {
    const generics = try Module.arena.alloc(Typ, self.generics.len);
    defer Module.arena.free(generics);
    for (generics, self.generics) |*target, generic| {
        target.* = try @call(.auto, fun, .{generic} ++ args);
    }
    return .{
        .name = self.name,
        .generics = try Typ.memo.save(generics),
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
    location: Location,

    pub fn checkDecl(self: @This(), items: std.StringHashMap(Item.Info), failer: *Failer) error{BadType}!?Typ {
        std.log.debug("checkTypDecl {f}", .{self.bare});
        const item = items.getPtr(self.bare.name) orelse {
            failer.fail(self.location, "item `{s}` is not declared", .{self.bare.name});
            return error.BadType;
        };
        switch (item.kind) {
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
