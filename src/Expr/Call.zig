const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,
context: Context,

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const callee = try self.expr.check(.{}, ctx);
    const info_call: okc.Expr.Info.Call = .{
        .args = self.args,
        .location = self.expr.location,
        .maybe_first = null,
        .typ = callee.typ,
    };
    return info_call.check(hint, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const callee = try self.expr.gen(ctx);
    var arg_typ_vals = try ctx.gpa.alloc(okc.Val.Typed, self.args.len);
    defer ctx.gpa.free(arg_typ_vals);
    for (arg_typ_vals, self.args, callee.typ.fun.params) |*target, arg, param| {
        target.* = try arg.gen(ctx);
        if (param == .slice and target.typ == .ptr) {
            target.* = try ctx.genArrayToSlice(target.typ.ptr.typ.array, target.bare);
        }
    }
    const ret_tmp = ctx.newTmp();
    if (callee.typ.fun.ret_typ.* != .prime or callee.typ.fun.ret_typ.prime != .void) {
        try ctx.buffer.?.print(ctx.gpa, "\n  %t{} = ", .{ret_tmp});
    } else {
        try ctx.buffer.?.print(ctx.gpa, "\n  ", .{});
    }
    try ctx.buffer.?.print(ctx.gpa, "call {f} {f} (", .{
        okc.Typ.LLPrinter{ .typ = callee.typ.fun.ret_typ.* },
        callee.bare,
    });
    if (self.args.len != 0) {
        try ctx.buffer.?.print(ctx.gpa, "{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try ctx.buffer.?.print(ctx.gpa, ", {f}", .{val});
        }
    }
    try ctx.buffer.?.print(ctx.gpa, ")", .{});
    return .{
        .typ = callee.typ.fun.ret_typ.*,
        .bare = .{ .tmp = ret_tmp },
    };
}

pub const Context = struct {
    fields: []const Field,

    pub fn parse(ctx: *okc.Parser) !@This() {
        try ctx.expect(.ctx, .quiet);
        try ctx.expect(.curl, .loud);
        const fields = try ctx.sep(Field.parse, .{});
        const prev = ctx.tokens[ctx.cursor - 1].lexeme;
        const endmode: okc.Parser.Mode = if (prev == .comma or prev == .curl) .quiet else .loud;
        try ctx.expect(.curr, endmode);
        return .{ .fields = fields };
    }

    pub const Field = struct {
        name: []const u8,
        expr: okc.Expr,
        location: okc.Location,

        pub fn parse(ctx: *okc.Parser) !@This() {
            const location = ctx.getLocation();
            const name = try ctx.parseName(.quiet);
            try ctx.expect(.equ, .loud);
            const expr = try okc.Expr.parse(ctx, .loud);
            return .{
                .name = name,
                .expr = expr,
                .location = location,
            };
        }
    };
};

pub const Postfix = struct {
    args: []okc.Expr,
    context: okc.Expr.Call.Context,

    pub fn parse(ctx: *okc.Parser) !@This() {
        try ctx.expect(.parl, .quiet);
        const args = try ctx.sep(okc.Expr.parse, .{.loud});
        const location = ctx.getLocation();
        const prev = ctx.tokens[ctx.cursor - 1].lexeme;
        const endmode: okc.Parser.Mode = if (prev == .comma or prev == .parl) .quiet else .loud;
        try ctx.expect(.parr, endmode);
        const context = try ctx.maybe(Context.parse, .{}) orelse Context{ .fields = &.{} };
        ctx.tmp_location = location;
        return .{
            .args = args,
            .context = context,
        };
    }
};
