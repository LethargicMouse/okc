const std = @import("std");

const okc = @import("okc");

pub const Field = @import("Struct/Field.zig");
pub const Named = @import("Struct/Named.zig");
const Typed = @import("Struct/Typed.zig");

fields: []Field,
typ: okc.Typ = .any,

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    if (self.typ.getName()) |name| {
        try name.genStruct(ctx);
    }
    try ctx.buffer.?.print(ctx.gpa, "{f} {{", .{okc.Typ.LLPrinter{ .typ = self.typ }});
    if (self.fields.len != 0) {
        const fields = try ctx.gpa.alloc(okc.Expr, self.fields.len);
        defer ctx.gpa.free(fields);
        if (self.typ.getName()) |typ_name| {
            for (ctx.structs.get(typ_name).?.default_fields) |field| {
                fields[field.index] = field.expr;
            }
        }
        for (self.fields) |field| {
            const info = self.typ.getFieldGenInfo(field.name, ctx.structs);
            fields[info.index] = field.expr;
        }
        try ctx.buffer.?.print(ctx.gpa, "\n  ", .{});
        _ = try fields[0].genConst(ctx);
        for (fields[1..]) |expr| {
            try ctx.buffer.?.print(ctx.gpa, ",\n  ", .{});
            _ = try expr.genConst(ctx);
        }
    }
    try ctx.buffer.?.print(ctx.gpa, "\n}}", .{});
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
        .prime, .ptr, .any, .array, .fun, .int, .typ => {
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
            const expected = okc.Typ{ .ptr = .{
                .typ = slice.typ,
                .mutable = slice.mutable,
            } };
            const info = try field.expr.check(.{ .typ = expected }, ctx);
            const typ = expected.unify(info.typ, field.expr.location, ctx.failer);
            was_ptr = if (typ == .ptr) typ.ptr.typ else try okc.Typ.memo.box(.err, ctx.arena);
        } else if (std.mem.eql(u8, field.name, "len")) {
            if (was_len) {
                ctx.failer.newFieldSecond(field.location, field.name);
            }
            const info = try field.expr.check(.{ .typ = .{ .prime = .u64 } }, ctx);
            const expected: okc.Typ = .{ .prime = .u64 };
            _ = expected.unify(info.typ, field.expr.location, ctx.failer);
            was_len = true;
        }
    }
    if (!was_len) {
        ctx.failer.notInit(location, "len");
    }
    if (was_ptr == null) {
        ctx.failer.notInit(location, "ptr");
    }
    self.typ = okc.Typ{ .slice = .{
        .typ = was_ptr.?,
        .mutable = slice.mutable,
    } };
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}
