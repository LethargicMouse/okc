const okc = @import("okc");

header: Header,
body: okc.Stmt.Block,

pub fn gen(
    self: @This(),
    name: okc.Typ.Name,
    fun_typ: okc.Typ.Fun,
    ctx: *okc.Codegen,
) !void {
    try ctx.extra_buffer.print(
        ctx.gpa,
        "\ndefine {f} @\"{f}\"(",
        .{ okc.Typ.LLPrinter{ .typ = fun_typ.ret_typ.* }, name },
    );
    var param_typ_vals = try ctx.gpa.alloc(okc.Val.Typed, self.header.params.len);
    defer ctx.gpa.free(param_typ_vals);
    if (self.header.params.len != 0) {
        param_typ_vals[0] = try okc.Item.Fun.Header.Param.gen(fun_typ.params[0], ctx);
        for (param_typ_vals[1..], fun_typ.params[1..]) |*target, param_typ| {
            try ctx.extra_buffer.print(ctx.gpa, ", ", .{});
            target.* = try okc.Item.Fun.Header.Param.gen(param_typ, ctx);
        }
    }
    try ctx.extra_buffer.print(ctx.gpa,
        \\) {{
        \\entry:
    , .{});
    for (
        param_typ_vals[0..self.header.params.len],
        self.header.params,
    ) |typ_val, param| {
        const vari = try typ_val.toStack(ctx);
        try ctx.vars.put(param.name, vari);
    }
    try self.body.gen(ctx);
    if (self.header.ret_typ.isVoid()) {
        try okc.Stmt.Return.gen(.{ .expr = null }, ctx);
    } else {
        try okc.Stmt.unre.gen(ctx);
    }
    try ctx.writer.interface.print("{s}{s}\n}}", .{ ctx.extra_buffer.items, ctx.buffer.items });
    ctx.extra_buffer.clearRetainingCapacity();
    ctx.vars.clearRetainingCapacity();
    ctx.resolve_map.clearRetainingCapacity();
    ctx.buffer.clearRetainingCapacity();
}

pub fn check(self: @This(), location: okc.Location, ctx: okc.Item.Check) !void {
    var stmt_check: okc.Stmt.Check = ctx.checkStmt(self.header.ret_typ);
    defer stmt_check.deinit();
    for (self.header.params) |param| {
        try stmt_check.declare(param.name, param.location, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        }, ctx.failer);
    }
    const control_flow = try self.body.check(&stmt_check);
    if (control_flow != .ret and !self.header.ret_typ.isVoid()) {
        ctx.failer.fail(location, "function may not return", .{});
    }
    stmt_check.freeVars(0);
}

pub const Extern = struct {
    header: Header,

    pub fn gen(self: @This(), name: []const u8, ctx: *okc.Codegen) !void {
        try ctx.writer.interface.print("\ndeclare {f} @{s}(", .{
            okc.Typ.LLPrinter{ .typ = self.header.ret_typ },
            name,
        });
        if (self.header.params.len != 0) {
            try ctx.writer.interface.print("{f}", .{okc.Typ.LLPrinter{ .typ = self.header.params[0].typ }});
            for (self.header.params[1..]) |param| {
                try ctx.writer.interface.print(", {f}", .{okc.Typ.LLPrinter{ .typ = param.typ }});
            }
        }
        try ctx.writer.interface.print(")", .{});
    }
};

pub const Header = struct {
    generics: []const okc.Item.Generic,
    params: []Param,
    ret_typ: okc.Typ,

    pub fn parse(ctx: *okc.Parser, mode: okc.Parser.Mode) !okc.Item.Fun.Header {
        try ctx.expect(.fun, mode);
        ctx.tmp_location = ctx.getLocation();
        ctx.tmp_name = try ctx.parseName(.loud);
        const generics = try ctx.maybe(okc.Parser.parseGenerics, .{}) orelse &.{};
        try ctx.expect(.parl, .loud);
        const params = try ctx.sep(okc.Parser.parseParam, .{});
        try ctx.expect(.parr, .loud);
        const ret_typ: okc.Typ = try .parse(ctx);
        return .{
            .generics = generics,
            .params = params,
            .ret_typ = ret_typ,
        };
    }

    pub fn check(self: *@This(), ctx: okc.Item.Check) !void {
        var generics_checker: okc.Item.Generic.Checker = try .init(ctx.gpa, self.generics);
        defer generics_checker.deinit(ctx.gpa);
        const typ_check = ctx.checkTyp(&generics_checker);
        for (self.params) |*param| {
            param.typ = try param.typ.check(typ_check);
        }
        self.ret_typ = try self.ret_typ.check(typ_check);
        generics_checker.checkUsage(ctx.failer);
    }

    pub const Param = struct {
        name: []const u8,
        typ: okc.Typ,
        location: okc.Location,

        pub fn gen(typ: okc.Typ, ctx: *okc.Codegen) !okc.Val.Typed {
            const tmp = ctx.counter.next();
            try ctx.extra_buffer.print(
                ctx.gpa,
                "{f} %t{}",
                .{ okc.Typ.LLPrinter{ .typ = typ }, tmp },
            );
            return .{ .typ = typ, .bare = .{ .tmp = tmp } };
        }
    };
};

pub const GenReq = struct {
    module: *okc.Module.GenInfo,
    name: okc.Typ.Name,
    fun: okc.Typ.Fun,

    pub fn handle(req: okc.Item.Fun.GenReq, ctx: *okc.Codegen) !void {
        ctx.module = req.module;
        const item = ctx.module.items.get(req.name.name).?;
        const fun = switch (item) {
            .typ_alias, .use => unreachable,
            .ext_fun => |ext_fun| {
                const was = try ctx.generated.getOrPut(req.name);
                if (was.found_existing) {
                    return;
                }
                try ext_fun.gen(req.name.name, ctx);
                return;
            },
            .fun => |fun| fun,
            .constant, .typ_decl => unreachable,
        };
        const was = try ctx.generated.getOrPut(req.name);
        if (was.found_existing) {
            return;
        }
        for (fun.header.generics, req.name.generics) |generic, typ| {
            try ctx.resolve_map.put(generic.name, typ);
        }
        try fun.gen(req.name, req.fun, ctx);
    }
};
