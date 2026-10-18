const std = @import("std");

const okc = @import("okc");

name: []const u8,
generics: []const okc.Typ = &.{},

pub fn getItems(self: @This(), items: std.StringHashMap(okc.Item.Info)) ?std.StringHashMap(okc.Item.Info) {
    const item = items.get(self.name).?;
    switch (item.kind) {
        .module => |mod| return mod.items,
        else => return null,
    }
}

pub fn genStruct(self: @This(), ctx: *okc.Codegen) error{ OutOfMemory, WriteFailed }!void {
    const was = try ctx.generated.getOrPut(self);
    if (was.found_existing) {
        return;
    }
    const buffer = ctx.buffer.?;
    ctx.buffer = .empty;
    defer {
        ctx.buffer.?.deinit(ctx.gpa);
        ctx.buffer = buffer;
    }
    var fields: std.StringHashMap(okc.Item.Struct.Field.GenInfo) = .init(ctx.gpa);
    errdefer fields.deinit();
    var default_fields_vec: std.ArrayList(okc.Item.Struct.Field.DefaultedGenInfo) = .empty;
    errdefer default_fields_vec.deinit(ctx.gpa);
    try ctx.buffer.?.print(ctx.gpa, "\n%\"{f}\" = type {{", .{self});
    const struc = try ctx.module.items.get(self.name).?.getStruct(self.name, ctx);
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    for (struc.generics, self.generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    var struct_layout = okc.Layout{ .size = 0, .alig = 1 };
    const field_typs = try ctx.gpa.alloc(okc.Typ, struc.fields.len);
    defer ctx.gpa.free(field_typs);
    for (field_typs, struc.fields, 0..) |*typ, field, i| {
        typ.* = try field.typ.resolve(resolve_map, ctx.arena);
        const layout = try ctx.getLayout(typ.*);
        struct_layout.add(layout);
        try fields.put(field.name, .{
            .typ = typ.*,
            .index = i,
        });
        if (field.default) |expr| {
            try default_fields_vec.append(ctx.gpa, .{
                .expr = expr,
                .index = i,
            });
        }
    }
    if (field_typs.len != 0) {
        try ctx.buffer.?.print(ctx.gpa, "\n  {f}", .{okc.Typ.LLPrinter{ .typ = field_typs[0] }});
        for (field_typs[1..]) |typ| {
            try ctx.buffer.?.print(ctx.gpa, ",\n  {f}", .{okc.Typ.LLPrinter{ .typ = typ }});
        }
    }
    try ctx.writer.interface.print("{s}\n}}", .{ctx.buffer.?.items});
    try ctx.structs.put(self, .{
        .fields = fields,
        .default_fields = try default_fields_vec.toOwnedSlice(ctx.gpa),
        .layout = struct_layout,
    });
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

    pub fn checkDecl(self: @This(), ctx: okc.Typ.Check) error{BadType}!?okc.Typ {
        std.log.debug("checkTypDecl {f}", .{self.bare});
        const name = if (std.mem.eql(u8, self.bare.name, "Self"))
            ctx.mod_typ.name
        else
            self.bare.name;
        const item = ctx.items.getPtr(name) orelse {
            ctx.failer.fail(self.location, "item `{s}` is not declared", .{self.bare.name});
            return error.BadType;
        };
        switch (item.kind) {
            .module => unreachable,
            .fun, .vari => {
                ctx.failer.fail(self.location, "item `{s}` is not a type", .{self.bare.name});
                return error.BadType;
            },
            .typ => |typ| {
                item.used = true;
                return typ;
            },
            .struc => |struc| {
                item.used = true;
                std.log.debug("item {s} used", .{name});
                if (struc.generics.len != self.bare.generics.len) {
                    ctx.failer.fail(
                        self.location,
                        "expected {} generics\n        found {}",
                        .{ struc.generics.len, self.bare.generics.len },
                    );
                }
                if (std.mem.eql(u8, self.bare.name, "Self")) {
                    return .{ .name = ctx.mod_typ };
                } else {
                    return null;
                }
            },
        }
    }
};
