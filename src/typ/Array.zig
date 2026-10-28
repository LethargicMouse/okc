const std = @import("std");

const okc = @import("okc");

index: Index,
typ: *const okc.Typ,

pub fn getLen(self: @This(), ctx: *okc.Codegen) !u64 {
    switch (self.index) {
        .len => |len| return len,
        .enumm => |name| {
            try okc.Item.Const.genNamed(name, ctx);
            return ctx.typ_decls.get(.{ .name = name }).?.variants.count();
        },
    }
}

pub fn parseTyp(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.bral, .quiet);
    const index: Index = try .parse(ctx);
    try ctx.expect(.brar, .loud);
    const typ = try ctx.maybe(okc.Typ.parse, .{}) orelse .any;
    const ptr = try okc.Typ.memo.box(typ, ctx.arena);
    return .{ .array = .{
        .index = index,
        .typ = ptr,
    } };
}

pub fn eql(a: @This(), b: @This()) bool {
    return a.index.eql(b.index) and a.typ == b.typ;
}

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    hasher.update(std.mem.asBytes(&self));
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.print("[{f}]{f}", .{ self.index, self.typ });
}

pub const Index = union(enum) {
    len: u64,
    enumm: []const u8,

    pub fn getTyp(self: @This()) okc.Typ {
        return switch (self) {
            .len => .{ .prime = .u64 },
            .enumm => |name| .{ .name = .{ .name = name } },
        };
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return switch (self) {
            .len => |len| other == .len and other.len == len,
            .enumm => |name| other == .enumm and std.mem.eql(u8, other.enumm, name),
        };
    }

    pub fn parse(ctx: *okc.Parser) !@This() {
        return ctx.either(.{ parseLen, parseEnumm });
    }

    fn parseLen(ctx: *okc.Parser) !@This() {
        const len = try ctx.parseInt();
        return .{ .len = len };
    }

    fn parseEnumm(ctx: *okc.Parser) !@This() {
        const enumm = try ctx.parseName(.quiet);
        return .{ .enumm = enumm };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        switch (self) {
            .len => |len| try writer.print("{}\n", .{len}),
            .enumm => |enumm| try writer.print("{s}\n", .{enumm}),
        }
    }
};
