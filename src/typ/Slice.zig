const std = @import("std");

const Typ = @import("mod.zig").Typ;

typ: *const Typ,
mutable: bool,

pub fn resolve(self: @This(), resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!@This() {
    const new = try self.typ.resolve(resolve_map);
    const ptr = try Typ.memo.box(new);
    return .{
        .typ = ptr,
        .mutable = self.mutable,
    };
}

pub fn eql(a: @This(), b: @This()) bool {
    return a.typ == b.typ and a.mutable == b.mutable;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self.typ));
    hasher.update(&.{@intFromBool(self.mutable)});
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll("[]");
    if (self.mutable) {
        try writer.writeAll("mut ");
    }
    try self.typ.format(writer);
}
