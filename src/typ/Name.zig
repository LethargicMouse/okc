const std = @import("std");

const okc = @import("okc");

name: []const u8,
generics: []const okc.Typ = &.{},

pub fn parseGenericTyp(ctx: *okc.Parser) !okc.Typ {
    const location = ctx.getLocation();
    const name = try ctx.parseName(.quiet);
    try ctx.expect(.les, .quiet);
    const generics = try ctx.sep(okc.Typ.parse, .{});
    try ctx.expect(.mor, .loud);
    return .{ .loc_name = .{
        .bare = .{
            .name = name,
            .generics = generics,
        },
        .location = location,
    } };
}

pub fn getItems(self: @This(), items: std.StringHashMap(okc.Item.Info)) ?std.StringHashMap(okc.Item.Info) {
    const item = items.get(self.name).?;
    switch (item.kind) {
        .module => |mod| return mod.items,
        else => return null,
    }
}

pub fn updateGenerics(
    self: @This(),
    fun: anytype,
    args: anytype,
    arena: std.mem.Allocator,
) !@This() {
    const generics = try arena.alloc(okc.Typ, self.generics.len);
    defer arena.free(generics);
    for (generics, self.generics) |*target, generic| {
        target.* = try @call(.auto, fun, .{generic} ++ args);
    }
    return .{
        .name = self.name,
        .generics = try okc.Typ.memo.save(generics, arena),
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
    location: okc.Location,
};
