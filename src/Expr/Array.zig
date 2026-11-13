const std = @import("std");

const okc = @import("okc");

typ_hint: ?okc.Typ,
exprs: []okc.Expr,
typ: okc.Typ = .any,

pub fn castToSlice(typ: okc.Typ.Array, val: okc.Val, ctx: *okc.Codegen) !okc.Val.Typed {
    std.log.debug("cast array ptr {f} to slice", .{typ});
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = typ.typ,
            .sized = true,
            .mutable = false,
        } },
        .bare = .undef,
    };
    const len = try typ.getLen(ctx);
    const ptr_typ = okc.Typ{ .slice = .{ .typ = typ.typ, .mutable = false, .sized = false } };
    if (len == 0) {
        try res.genIV(.{ .typ = ptr_typ, .bare = .nullptr }, 0, ctx);
    } else {
        try res.genIV(.{ .typ = ptr_typ, .bare = val }, 0, ctx);
    }
    try res.genIV(.{ .typ = .{ .prime = .u64 }, .bare = .{ .int = len } }, 1, ctx);
    return res;
}

pub fn parseExpr(ctx: *okc.Parser) !okc.Expr {
    const start = ctx.getLocation();
    const mtyp = try ctx.maybe(parseTypHint, .{});
    try ctx.expect(.bral, .quiet);
    const exprs = try ctx.sep(okc.Expr.parse, .{.loud});
    if (try ctx.maybe(okc.Parser.expect, .{ .equ, .quiet }) != null) {
        return Indexed.parseExpr(ctx, start, exprs);
    }
    const end = ctx.getLocation();
    try ctx.expect(.brar, .loud);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .typ_hint = mtyp,
        } },
    };
}

fn parseTypHint(ctx: *okc.Parser) !okc.Typ {
    try ctx.expect(.les, .quiet);
    const typ: okc.Typ = try .parse(ctx);
    try ctx.expect(.mor, .loud);
    return typ;
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    var inner_typ = try self.typ.solve(ctx.gpa, ctx.arena);
    inner_typ = try inner_typ.resolve(.{
        .gpa = ctx.gpa,
        .arena = ctx.arena,
        .map = ctx.resolve_map,
    });
    var res = okc.Val.Typed{
        .typ = .{ .array = .{
            .typ = try okc.Typ.memo.box(inner_typ, ctx.arena),
            .index = .{ .len = self.exprs.len },
        } },
        .bare = .undef,
    };
    for (self.exprs, 0..) |expr, i| {
        const typ_val = try expr.gen(ctx);
        try res.genIV(typ_val, i, ctx);
    }
    return res;
}

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    const typ = okc.Typ{ .array = .{
        .typ = try okc.Typ.memo.box(self.typ, ctx.arena),
        .index = .{ .len = self.exprs.len },
    } };
    try ctx.buffer.print(ctx.gpa, "{f} [", .{okc.Typ.LLPrinter{ .typ = typ }});
    if (self.exprs.len != 0) {
        try ctx.buffer.print(ctx.gpa, "\n  ", .{});
        _ = try self.exprs[0].genConst(ctx);
        for (self.exprs[1..]) |expr| {
            try ctx.buffer.print(ctx.gpa, ",\n  ", .{});
            _ = try expr.genConst(ctx);
        }
    }
    try ctx.buffer.print(ctx.gpa, "\n]", .{});
    return typ;
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    var inner_hint: okc.Typ = .any;
    if (self.typ_hint) |typ| {
        const checked = try typ.check(ctx.typCheckCtx());
        self.typ = checked;
        inner_hint = checked;
    } else if (hint == .array) {
        inner_hint = hint.array.typ.*;
    }
    if (self.exprs.len == 0) {
        return .{
            .typ = .{ .array = .{
                .typ = try okc.Typ.memo.box(.{ .lazy = .from(&self.typ) }, ctx.arena),
                .index = .{ .len = 0 },
            } },
            .mutable = true,
        };
    }
    for (self.exprs) |*expr| {
        const info = try expr.check(.{ .typ = inner_hint }, ctx);
        self.typ = info.typ.unify(self.typ, expr.location, ctx.failer);
    }
    return .{
        .typ = .{ .array = .{
            .typ = try okc.Typ.memo.box(self.typ, ctx.arena),
            .index = .{ .len = self.exprs.len },
        } },
        .mutable = false,
    };
}

pub const Indexed = struct {
    mtyp: ?okc.Typ,
    assocs: []Assoc,
    typ: okc.Typ = .any,

    pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
        var res = okc.Val.Typed{
            .typ = try self.typ.solve(ctx.gpa, ctx.arena),
            .bare = .undef,
        };
        switch (res.typ.array.index) {
            .len => {},
            .enumm => |name| {
                try okc.Item.TypDecl.genNamed(.{ .name = name }, ctx);
                res.typ.array.index =
                    .{ .len = ctx.typ_decls.get(.{ .name = name }).?.variants.count() };
            },
        }
        for (self.assocs) |assoc| {
            const val = try assoc.expr.gen(ctx);
            for (assoc.indices) |index_expr| {
                const index = try index_expr.genInt(ctx);
                try res.genIV(val, index, ctx);
            }
        }
        return res;
    }

    pub fn check(self: *@This(), hint: okc.Typ, location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
        var inner_typ: okc.Typ = .any;
        var inner_hint: okc.Typ = .any;
        var index_typ: okc.Typ = .any;
        if (hint == .array) {
            inner_hint = hint.array.typ.*;
            index_typ = hint.array.index.getTyp();
        }
        if (self.mtyp) |typ| {
            inner_typ = typ;
            inner_hint = typ;
        }
        std.debug.assert(self.assocs.len != 0);
        for (self.assocs) |*assoc| {
            for (assoc.indices) |*index| {
                const info = try index.check(.{ .typ = index_typ }, ctx);
                index_typ = info.typ.unify(index_typ, index.location, ctx.failer);
            }
            const info = try assoc.expr.check(.{ .typ = inner_hint }, ctx);
            inner_typ = info.typ.unify(inner_typ, assoc.expr.location, ctx.failer);
        }
        const norm = index_typ.normalise();
        if (norm == .err) {
            return .{ .typ = .err, .mutable = false };
        }
        if (norm == .any) {
            ctx.failer.cannotInfer(norm, location);
            return .{ .typ = .err, .mutable = false };
        }
        const name_typ = if (norm == .name) norm.name else {
            ctx.failer.fail(location, "array cannot be indexed by `{f}`", .{norm});
            return .{ .typ = .err, .mutable = false };
        };
        self.typ = .{ .array = .{
            .typ = try okc.Typ.memo.box(inner_typ, ctx.arena),
            .index = .{ .enumm = name_typ.name },
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }

    pub fn parseExpr(ctx: *okc.Parser, start: okc.Location, first_indices: []okc.Expr) !okc.Expr {
        const first_expr: okc.Expr = try .parse(ctx, .loud);
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
            .kind = .{ .i_array = .{
                .assocs = assocs,
                .mtyp = null,
            } },
        };
    }

    pub const Assoc = struct {
        indices: []okc.Expr,
        expr: okc.Expr,

        pub fn parse(ctx: *okc.Parser) !@This() {
            try ctx.expect(.comma, .quiet);
            const indices = try ctx.sep(okc.Expr.parse, .{.loud});
            if (indices.len == 0) {
                return error.ParseFailed;
            }
            try ctx.expect(.equ, .loud);
            const expr: okc.Expr = try .parse(ctx, .loud);
            return .{
                .indices = indices,
                .expr = expr,
            };
        }
    };
};
