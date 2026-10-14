const std = @import("std");

const ast = @import("../ast/mod.zig");
const Location = @import("../Location.zig");
const Typ = @import("mod.zig").Typ;

name: []const u8,
generics: []const Typ = &.{},

pub fn updateGenerics(self: @This(), fun: anytype, args: anytype) !@This() {
    const generics = try ast.arena.allocator().alloc(Typ, self.generics.len);
    defer ast.arena.allocator().free(generics);
    for (generics, self.generics) |*target, generic| {
        target.* = try @call(.auto, fun, .{generic} ++ args);
    }
    return .{
        .name = self.name,
        .generics = try Typ.memo.save(generics),
    };
}

pub fn resolve(self: @This(), resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!@This() {
    return self.updateGenerics(Typ.resolve, .{resolve_map});
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
};
