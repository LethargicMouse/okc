const std = @import("std");

const okc = @import("okc");

pub const Field = @import("Struct/Field.zig");
pub const Named = @import("Struct/Named.zig");
const Typed = @import("Struct/Typed.zig");

fields: []Field,
typ: okc.Typ = .any,

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    const location = ctx.getLocation();
    try ctx.expect(.dot, .quiet);
    const fields = try okc.Expr.Struct.parseBody(ctx);
    return .{
        .location = location,
        .kind = .{ .struc = .{ .fields = fields } },
    };
}

pub fn parseBody(ctx: *okc.Parser) ![]Field {
    try ctx.expect(.curl, .quiet);
    const fields = try ctx.sep(okc.Expr.Struct.Field.parse, .{});
    try ctx.expect(.curr, .loud);
    return fields;
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    std.log.debug("gen expr struct of type `{f}`", .{self.typ});
    var typ = try self.typ.solve(ctx.gpa, ctx.arena);
    typ = try self.typ.resolve(.{
        .gpa = ctx.gpa,
        .arena = ctx.arena,
        .map = ctx.resolve_map,
    });
    if (typ == .name) {
        try okc.Item.TypDecl.genNamed(typ.name, ctx);
    }
    var res = okc.Val.Typed{
        .typ = typ,
        .bare = .undef,
    };
    if (typ == .name) {
        for (ctx.typ_decls.get(typ.name).?.default_fields) |field| {
            var typ_val = try field.expr.gen(ctx);
            if (field.typ == .slice and typ_val.typ == .ptr) {
                typ_val = try okc.Expr.Array.castToSlice(
                    typ_val.typ.ptr.typ.array,
                    typ_val.bare,
                    ctx,
                );
            }
            try res.genIV(typ_val, field.index, ctx);
        }
    }
    for (self.fields) |field| {
        var typ_val = try field.expr.gen(ctx);
        const info = try okc.Item.TypDecl.Field.GenInfo.get(typ, field.name, ctx);
        if (info.typ == .slice and typ_val.typ == .ptr) {
            typ_val = try okc.Expr.Array.castToSlice(
                typ_val.typ.ptr.typ.array,
                typ_val.bare,
                ctx,
            );
        }
        try res.genIV(typ_val, info.index, ctx);
    }
    return res;
}

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    if (self.typ == .name) {
        try okc.Item.TypDecl.genNamed(self.typ.name, ctx);
    }
    try ctx.buffer.print(ctx.gpa, "{f} {{", .{okc.Typ.LLPrinter{ .typ = self.typ }});
    if (self.fields.len != 0) {
        const fields = try ctx.gpa.alloc(okc.Expr, self.fields.len);
        defer ctx.gpa.free(fields);
        if (self.typ == .name) {
            for (ctx.typ_decls.get(self.typ.name).?.default_fields) |field| {
                fields[field.index] = field.expr;
            }
        }
        for (self.fields) |field| {
            const info = try okc.Item.TypDecl.Field.GenInfo.get(self.typ, field.name, ctx);
            fields[info.index] = field.expr;
        }
        try ctx.buffer.print(ctx.gpa, "\n  ", .{});
        _ = try fields[0].genConst(ctx);
        for (fields[1..]) |expr| {
            try ctx.buffer.print(ctx.gpa, ",\n  ", .{});
            _ = try expr.genConst(ctx);
        }
    }
    try ctx.buffer.print(ctx.gpa, "\n}}", .{});
    return self.typ;
}

pub fn check(
    self: *@This(),
    location: okc.Location,
    hint: okc.Typ,
    ctx: okc.Expr.Check,
) error{OutOfMemory}!okc.Expr.Info {
    const err = okc.Expr.Info{
        .typ = .err,
        .mutable = false,
    };
    const name = switch (hint) {
        .loc_name => |located| located.bare,
        .name => |name| name,
        .slice => |slice| return self.checkSlice(slice, location, ctx),
        .err => return err,
        .lazy => unreachable,
        .prime, .ptr, .any, .array, .fun, .int, .typ, .never => {
            ctx.failer.cannotInfer(.any, location);
            for (self.fields) |*field| {
                _ = try field.expr.check(.{}, ctx);
            }
            return err;
        },
    };
    return self.typed(name).check(location, ctx);
}

pub fn typed(self: *@This(), typ: okc.Typ.Name) Typed {
    return .{ .bare = self, .typ = typ };
}

fn checkSlice(
    self: *@This(),
    slice: okc.Typ.Slice,
    location: okc.Location,
    ctx: okc.Expr.Check,
) !okc.Expr.Info {
    var was_ptr: ?*const okc.Typ = null;
    var was_len = false;
    for (self.fields) |*field| {
        if (std.mem.eql(u8, field.name, "ptr")) {
            if (was_ptr) |_| {
                ctx.failer.newFieldSecond(field.location, field.name);
            }
            const expected = okc.Typ{ .slice = .{
                .typ = slice.typ,
                .mutable = slice.mutable,
                .sized = false,
            } };
            const info = try field.expr.check(.{ .typ = expected }, ctx);
            const typ = info.typ.unify(expected, field.expr.location, ctx.failer);
            was_ptr = if (typ == .slice) typ.slice.typ else try okc.Typ.memo.box(.err, ctx.arena);
        } else if (std.mem.eql(u8, field.name, "len")) {
            if (was_len) {
                ctx.failer.newFieldSecond(field.location, field.name);
            }
            const info = try field.expr.check(.{ .typ = .{ .prime = .u64 } }, ctx);
            _ = info.typ.unify(.{ .prime = .u64 }, field.expr.location, ctx.failer);
            was_len = true;
        }
    }
    if (!was_len) {
        ctx.failer.notInit(location, "len", "[]");
    }
    if (was_ptr == null) {
        ctx.failer.notInit(location, "ptr", "[]");
    }
    self.typ = okc.Typ{ .slice = .{
        .typ = was_ptr.?,
        .sized = true,
        .mutable = slice.mutable,
    } };
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
