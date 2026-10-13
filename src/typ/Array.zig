const std = @import("std");

const Typ = @import("mod.zig").Typ;

const Self = @This();
len: u64,
typ: *const Typ,

pub fn resolve(self: Self, resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!Self {
    const new = try self.typ.resolve(resolve_map);
    const new_ptr = try Typ.memo.box(new);
    return .{
        .len = self.len,
        .typ = new_ptr,
    };
}

pub fn eql(a: Self, b: Self) bool {
    return a.len == b.len and a.typ == b.typ;
}

pub fn hashIn(self: Self, hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self));
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("[{}]{f}", .{ self.len, self.typ });
}
