const std = @import("std");

const okc = @import("okc");

pub const GenInfo = @import("TypDecl/GenInfo.zig");
pub const Info = @import("TypDecl/Info.zig");
pub const Variant = @import("TypDecl/Variant.zig");

generics: []const okc.Item.Generic,
fields: []Field,
variants: []const Variant,

pub fn genNamed(name_typ: okc.Typ.Name, ctx: *okc.Codegen) error{ OutOfMemory, WriteFailed }!void {
    std.log.debug("gen typ decl `{f}` in mod `{s}`", .{ name_typ, ctx.module.name });
    const item = ctx.module.items.get(name_typ.name).?;
    switch (item) {
        .typ_decl => |decl| try decl.gen(name_typ, ctx),
        .use => {
            const module: *okc.Module.GenInfo = try .get(name_typ.name, ctx);
            try module.items.get(name_typ.name).?.typ_decl.gen(name_typ, ctx);
        },
        else => unreachable,
    }
}

pub fn gen(self: @This(), name: okc.Typ.Name, ctx: *okc.Codegen) !void {
    const was = try ctx.generated.getOrPut(name);
    if (was.found_existing) {
        return;
    }
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(ctx.gpa);
    var fields: std.StringHashMap(Field.GenInfo) = .init(ctx.gpa);
    errdefer fields.deinit();
    var variants: std.StringHashMap(usize) = .init(ctx.gpa);
    errdefer variants.deinit();
    var default_fields_vec: std.ArrayList(Field.DefaultedGenInfo) = .empty;
    errdefer default_fields_vec.deinit(ctx.gpa);
    var resolve_map: std.StringHashMap(okc.Typ) = .init(ctx.gpa);
    defer resolve_map.deinit();
    for (self.generics, name.generics) |generic, g_typ| {
        try resolve_map.put(generic.name, g_typ);
    }
    var struct_layout = okc.Layout{ .size = 0, .alig = 1 };
    const field_typs = try ctx.gpa.alloc(okc.Typ, self.fields.len + @intFromBool(self.variants.len != 0));
    defer ctx.gpa.free(field_typs);
    var field_typs_to_init = field_typs;
    if (self.variants.len != 0) {
        field_typs[0] = .{ .prime = .u32 };
        field_typs_to_init = field_typs[1..];
        for (self.variants, 0..) |variant, i| {
            try variants.put(variant.name, i);
        }
    }
    for (field_typs_to_init, self.fields, 0..) |*f_typ, field, i| {
        f_typ.* = try field.typ.resolve(resolve_map, ctx.arena);
        const layout = try f_typ.getLayout(ctx);
        struct_layout.add(layout);
        try fields.put(field.name, .{
            .typ = f_typ.*,
            .index = i,
        });
        if (field.default) |expr| {
            try default_fields_vec.append(ctx.gpa, .{
                .expr = expr,
                .index = i,
            });
        }
    }
    try buffer.print(ctx.gpa, "\n%\"{f}\" = type {{", .{name});
    if (field_typs.len != 0) {
        try buffer.print(ctx.gpa, "\n  {f}", .{okc.Typ.LLPrinter{ .typ = field_typs[0] }});
        for (field_typs[1..]) |f_typ| {
            try buffer.print(ctx.gpa, ",\n  {f}", .{okc.Typ.LLPrinter{ .typ = f_typ }});
        }
    }
    try ctx.writer.interface.print("{s}\n}}", .{buffer.items});
    try ctx.typ_decls.put(name, .{
        .fields = fields,
        .variants = variants,
        .default_fields = try default_fields_vec.toOwnedSlice(ctx.gpa),
        .layout = struct_layout,
    });
}

pub fn parse(ctx: *okc.Parser) !@This() {
    try ctx.expect(.typ, .quiet);
    const location = ctx.getLocation();
    const name = try ctx.parseName(.loud);
    const generics = try ctx.maybe(okc.Parser.parseGenerics, .{}) orelse &.{};
    try ctx.expect(.curl, .loud);
    const fields = try ctx.sep(okc.Parser.parseFieldDecl, .{});
    var variants: []const Variant = &.{};
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    if (prev == .comma or prev == .curl) {
        variants = try ctx.sep(Variant.parse, .{});
    }
    try ctx.expect(.curr, .loud);
    ctx.tmp_location = location;
    ctx.tmp_name = name;
    return .{
        .generics = generics,
        .fields = fields,
        .variants = variants,
    };
}

pub fn makeInfo(self: @This(), ctx: okc.Item.Check) !Info {
    try ctx.checkGenericsRedeclare(self.generics);
    var res = Info{
        .generics = self.generics,
        .fields = .init(ctx.gpa),
        .variants = .init(ctx.gpa),
    };
    for (self.fields) |*field| {
        var defaulted = false;
        if (field.default) |*expr| {
            const expr_typ = try expr.checkConst(.{ .typ = field.typ }, ctx.checkExprCtx());
            _ = expr_typ.unify(field.typ, expr.location, ctx.failer);
            defaulted = true;
        }
        if (res.fields.get(field.name)) |prev| {
            ctx.failer.alreadyDeclared(field.location, field.name, prev.location);
            continue;
        }
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = field.typ,
            .defaulted = defaulted,
            .used = field.name[0] == '_',
        });
    }
    for (self.variants) |variant| {
        if (res.variants.get(variant.name)) |prev| {
            ctx.failer.alreadyDeclared(variant.location, variant.name, prev.location);
            continue;
        }
        try res.variants.put(variant.name, .{ .location = variant.location });
    }
    return res;
}

pub const Field = struct {
    name: []const u8,
    typ: okc.Typ,
    default: ?okc.Expr,
    location: okc.Location,

    pub const Info = struct {
        location: okc.Location,
        typ: okc.Typ,
        defaulted: bool,
        used: bool = false,
    };

    pub const DefaultedGenInfo = struct {
        index: usize,
        expr: okc.Expr,
    };

    pub const GenInfo = struct {
        index: usize,
        typ: okc.Typ,
    };
};
