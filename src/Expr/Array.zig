const std = @import("std");

const okc = @import("okc");

mtyp: ?okc.Typ,
exprs: []okc.Expr,
typ: okc.Typ = .any,

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    const start = ctx.getLocation();
    const mtyp = try ctx.maybe(okc.Parser.parseTypHint, .{});
    try ctx.expect(.bral, .quiet);
    const exprs = try ctx.sep(okc.Parser.parseExpr, .{.loud});
    if (try ctx.maybe(okc.Parser.expect, .{ .equ, .quiet }) != null) {
        return Indexed.parseExpr(ctx, start, exprs);
    }
    const end = ctx.getLocation();
    try ctx.expect(.brar, .loud);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .mtyp = mtyp,
            .typ = undefined,
        } },
    };
}

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    try ctx.buffer.?.print(ctx.gpa, "{f} [", .{okc.Typ.LLPrinter{ .typ = self.typ }});
    if (self.exprs.len != 0) {
        try ctx.buffer.?.print(ctx.gpa, "\n  ", .{});
        _ = try self.exprs[0].genConst(ctx);
        for (self.exprs[1..]) |expr| {
            try ctx.buffer.?.print(ctx.gpa, ",\n  ", .{});
            _ = try expr.genConst(ctx);
        }
    }
    try ctx.buffer.?.print(ctx.gpa, "\n]", .{});
    return self.typ;
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    var inner_typ: okc.Typ = .any;
    var inner_hint: okc.Typ = .any;
    if (self.mtyp) |typ| {
        inner_typ = typ;
        inner_hint = typ;
    } else if (hint == .array) {
        inner_hint = hint.array.typ.*;
    }
    if (self.exprs.len == 0) {
        const typ = okc.Typ{ .array = .{
            .typ = try okc.Typ.memo.box(inner_hint, ctx.arena),
            .len = 0,
        } };
        return .{
            .typ = typ,
            .mutable = false,
        };
    }
    for (self.exprs) |*expr| {
        const info = try expr.check(.{ .typ = inner_hint }, ctx);
        inner_typ = info.typ.unify(inner_typ, expr.location, ctx.failer);
    }
    self.typ = okc.Typ{ .array = .{
        .typ = try okc.Typ.memo.box(inner_typ, ctx.arena),
        .len = self.exprs.len,
    } };
    return .{
        .typ = self.typ,
        .mutable = false,
    };
}

pub const Indexed = struct {
    assocs: []Assoc,

    pub fn parseExpr(ctx: *okc.Parser, start: okc.Location, first_indices: []okc.Expr) !okc.Expr {
        const first_expr = try ctx.parseExpr(.loud);
        var vec: std.ArrayList(Assoc) = .empty;
        defer vec.deinit(ctx.gpa);
        try vec.append(ctx.gpa, .{
            .indices = first_indices,
            .expr = first_expr,
        });
        const assocs = try ctx.manyTo(&vec, Assoc.parse, .{});
        _ = try ctx.maybe(okc.Parser.expect, .{ .comma, .quiet });
        const end = ctx.getLocation();
        try ctx.expect(.brar, .loud);
        return .{
            .location = start.combine(end),
            .kind = .{ .i_array = .{ .assocs = assocs } },
        };
    }

    pub const Assoc = struct {
        indices: []okc.Expr,
        expr: okc.Expr,

        pub fn parse(ctx: *okc.Parser) !@This() {
            try ctx.expect(.comma, .quiet);
            const indices = try ctx.sep(okc.Parser.parseExpr, .{.loud});
            if (indices.len == 0) {
                return error.ParseFailed;
            }
            try ctx.expect(.equ, .loud);
            const expr = try ctx.parseExpr(.loud);
            return .{
                .indices = indices,
                .expr = expr,
            };
        }
    };
};
