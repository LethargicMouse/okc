const std = @import("std");

const Typ = @import("mod.zig").Typ;

typ: *const Typ,
mutable: bool,

pub fn eql(a: @This(), b: @This()) bool {
    return a.typ == b.typ and a.mutable == b.mutable;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self.typ));
    hasher.update(&.{@intFromBool(self.mutable)});
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    if (self.mutable) {
        try writer.print("&mut {f}", .{self.typ});
    } else {
        try writer.print("&{f}", .{self.typ});
    }
}
