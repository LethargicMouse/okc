const std = @import("std");

const Typ = @import("mod.zig").Typ;

len: u64,
typ: *const Typ,

pub fn eql(a: @This(), b: @This()) bool {
    return a.len == b.len and a.typ == b.typ;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self));
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.print("[{}]{f}", .{ self.len, self.typ });
}
