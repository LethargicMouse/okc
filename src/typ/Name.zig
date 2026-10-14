const std = @import("std");

const ast = @import("../ast/mod.zig");
const Location = @import("../Location.zig");
const Typ = @import("mod.zig").Typ;

const Self = @This();
name: []const u8,
generics: []const Typ = &.{},

pub fn updateGenerics(self: Self, fun: anytype, args: anytype) !Self {
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

pub fn resolve(self: Self, resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!Self {
    return self.updateGenerics(Typ.resolve, .{resolve_map});
}

pub fn eql(a: Self, b: Self) bool {
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

pub fn hashIn(self: Self, hasher: *std.hash.Wyhash) void {
    hasher.update(self.name);
    // `self.name` determines number of `self.generics`
    for (self.generics) |gen| {
        gen.hashIn(hasher);
    }
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.writeAll(self.name);
    if (self.generics.len != 0) {
        try writer.print("<{f}", .{self.generics[0]});
        for (self.generics[1..]) |generic| {
            try writer.print(", {f}", .{generic});
        }
        try writer.writeByte('>');
    }
}

pub const Located = struct {
    name: Self,
    location: Location,
};
