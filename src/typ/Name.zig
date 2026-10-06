const std = @import("std");

const Location = @import("../Location.zig");
const Resolver = @import("../resolver.zig").Resolver;
const Typ = @import("mod.zig").Typ;

const Self = @This();
name: []const u8,
generics: []const Typ = &.{},

pub fn resolve(name: @This(), resolver: *Resolver(Typ)) error{OutOfMemory}!@This() {
    const generics = try resolver.memo.arena.allocator().alloc(Typ, name.generics.len);
    for (generics, name.generics) |*target, generic| {
        target.* = try generic.resolve(resolver);
    }
    return .{
        .name = name.name,
        .generics = generics,
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

pub fn hashIn(name: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(name.name);
    // `name.name` determines number of `name.generics`
    for (name.generics) |gen| {
        gen.hashIn(hasher);
    }
}

pub fn format(name: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll(name.name);
    if (name.generics.len != 0) {
        try writer.print("<{f}", .{name.generics[0]});
        for (name.generics[1..]) |generic| {
            try writer.print(", {f}", .{generic});
        }
        try writer.writeByte('>');
    }
}

pub const Located = struct {
    name: Self,
    location: Location,
};
