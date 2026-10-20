const std = @import("std");

const okc = @import("okc");

generics: []const okc.Item.Generic,
fields: []Field,
variants: []const []const u8,

pub fn parse(ctx: *okc.Parser) !@This() {
    try ctx.expect(.typ, .quiet);
    const location = ctx.getLocation();
    const name = try ctx.parseName(.loud);
    const generics = try ctx.maybe(okc.Parser.parseGenerics, .{}) orelse &.{};
    try ctx.expect(.curl, .loud);
    const fields = try ctx.sep(okc.Parser.parseFieldDecl, .{});
    var variants: []const []const u8 = &.{};
    const prev = ctx.tokens[ctx.cursor - 1].lexeme;
    if (prev == .comma or prev == .curl) {
        variants = try ctx.sep(okc.Parser.parseName, .{.quiet});
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

pub fn reg(self: @This(), ctx: okc.Item.Check) !Info {
    try ctx.checkGenericsRedeclare(self.generics);
    var res = @This().Info{
        .generics = self.generics,
        .fields = .init(ctx.gpa),
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

pub const Info = struct {
    generics: []const okc.Item.Generic,
    fields: std.StringHashMap(Field.Info),

    pub fn checkUsage(self: @This(), failer: *okc.Failer) void {
        var iter = self.fields.iterator();
        while (iter.next()) |entry| {
            if (!entry.value_ptr.used) {
                failer.unused(entry.value_ptr.location, entry.key_ptr.*);
            }
        }
    }

    pub fn deinit(self: *@This()) void {
        self.fields.deinit();
        self.* = undefined;
    }
};

pub const GenInfo = struct {
    fields: std.StringHashMap(Field.GenInfo),
    default_fields: []const Field.DefaultedGenInfo,
    layout: okc.Layout,
};
