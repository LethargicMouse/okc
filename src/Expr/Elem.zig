const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,
index: okc.Expr,

pub fn parsePostfix(ctx: *okc.Parser) !okc.Expr.Postfix {
    try ctx.expect(.bral, .quiet);
    const index: okc.Expr = try .parse(ctx, .loud);
    const location = ctx.getLocation();
    try ctx.expect(.brar, .loud);
    return .{
        .location = location,
        .kind = .{ .elem = index },
    };
}

pub fn genOnVals(ref: okc.Val.Ref, index: okc.Val.Typed, ctx: *okc.Codegen) !okc.Val.Ref {
    std.log.debug("gen expr elem on ref typed `{f}`", .{ref.inner_typ});
    switch (ref.inner_typ) {
        .array => {
            const tmp = try ref.genGEPIB(index, ctx);
            return .{
                .inner_typ = ref.inner_typ.array.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        .slice => |slice| {
            var ptr: u32 = std.math.maxInt(u32);
            if (slice.sized) {
                const ptrptr = try ref.genGEPIB(.int(0), ctx);
                const ptrref: okc.Val.Ref = .{
                    .inner_typ = .{ .ptr = .{
                        .typ = slice.typ,
                        .mutable = false,
                    } },
                    .val = .{ .tmp = ptrptr },
                };
                ptr = try ptrref.load(ctx);
            } else {
                ptr = try ref.load(ctx);
            }
            const tmp = ctx.counter.next();
            try ctx.buffer.print(
                ctx.gpa,
                "\n  %t{} = getelementptr {f}, ptr %t{}, {f}",
                .{ tmp, okc.Typ.LLPrinter{ .typ = slice.typ.* }, ptr, index },
            );
            return .{
                .inner_typ = slice.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        else => unreachable,
    }
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) !okc.Val.Ref {
    const ref = try self.expr.genRef(ctx);
    var index_ref = try self.index.genRef(ctx);
    var index: okc.Val.Typed = undefined;
    if (index_ref.inner_typ == .name) {
        index = .{
            .typ = .{ .prime = .u32 },
            .bare = .{ .tmp = try index_ref.loadTag(ctx) },
        };
    } else {
        index = try index_ref.loadTypVal(ctx);
    }
    return genOnVals(ref, index, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const ref = try self.genRef(ctx);
    return ref.loadTypVal(ctx);
}

pub fn check(self: *@This(), location: okc.Location, ctx: okc.Expr.Check) !okc.Expr.Info {
    const info = try self.expr.check(.{}, ctx);
    const index = try self.index.check(.{}, ctx);
    const expected: okc.Typ = switch (info.typ.normalise()) {
        .array => |array| array.index.getTyp(),
        else => .{ .prime = .u64 },
    };
    _ = index.typ.unify(expected, self.index.location, ctx.failer);
    return info.getElem(location, ctx.failer) orelse .{
        .typ = .err,
        .mutable = true,
    };
}
