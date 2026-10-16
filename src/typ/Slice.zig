const std = @import("std");

const okc = @import("okc");

typ: *const okc.Typ,
mutable: bool,

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

pub fn checkField(
    self: @This(),
    mutable: bool,
    name: []const u8,
    location: okc.Location,
    failer: *okc.Failer,
) !okc.Expr.Info {
    if (std.mem.eql(u8, name, "ptr")) {
        return .{
            .typ = .{ .ptr = .{
                .typ = self.typ,
                .mutable = self.mutable,
            } },
            .mutable = mutable,
        };
    }
    if (std.mem.eql(u8, name, "len")) {
        return .{
            .typ = .{ .prime = .u64 },
            .mutable = mutable,
        };
    }
    failer.noField(location, name, .{ .slice = self });
    return .{
        .typ = .err,
        .mutable = true,
    };
}
