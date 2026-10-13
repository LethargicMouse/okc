const std = @import("std");

const Location = @import("../Location.zig");
const Typ = @import("mod.zig").Typ;

const Self = @This();
name: []const u8,
generics: []const Typ = &.{},

pub fn resolve(self: Self, resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!Self {
    const generics = try Typ.memo.alloc(self.generics.len);
    defer Typ.memo.free(generics);
    for (generics, self.generics) |*target, generic| {
        target.* = try generic.resolve(resolve_map);
    }
    return .{
        .name = self.name,
        .generics = try Typ.memo.save(generics),
    };
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
