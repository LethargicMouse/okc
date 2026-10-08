const std = @import("std");

const Typ = @import("mod.zig").Typ;
const Resolver = @import("../resolver.zig").Resolver;

const Self = @This();
typ: *const Typ,
mutable: bool,

pub fn resolve(self: Self, resolver: Resolver(Typ)) error{OutOfMemory}!Self {
    const new = try self.typ.resolve(resolver);
    const new_ptr = try resolver.mem.box(new);
    return .{
        .typ = new_ptr,
        .mutable = self.mutable,
    };
}

pub fn eql(a: Self, b: Self) bool {
    return a.typ == b.typ and a.mutable == b.mutable;
}

pub fn hashIn(self: Self, hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self.typ));
    hasher.update(&.{@intFromBool(self.mutable)});
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    if (self.mutable) {
        try writer.print("&mut {f}", .{self.typ});
    } else {
        try writer.print("&{f}", .{self.typ});
    }
}
