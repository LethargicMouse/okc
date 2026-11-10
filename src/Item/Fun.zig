const std = @import("std");

const okc = @import("okc");

header: Header,
body: okc.Stmt.Block,

pub const Extern = @import("Fun/Extern.zig");
pub const Header = @import("Fun/Header.zig");
pub const Param = @import("Fun/Param.zig");

pub fn parseItem(ctx: *okc.Parser) !okc.Item {
    const header: Header = try .parse(ctx, .quiet);
    const location = ctx.tmp_location;
    const name = ctx.tmp_name;
    const body: okc.Stmt.Block = try .parse(ctx);
    return .{
        .name = name,
        .location = location,
        .kind = .{ .fun = .{
            .header = header,
            .body = body,
        } },
    };
}

pub fn gen(
    self: @This(),
    name: okc.Typ.Name,
    fun_typ: okc.Typ.Fun,
    ctx: *okc.Codegen,
) !void {
    ctx.context = self.header.context;
    try ctx.extra_buffer.print(
        ctx.gpa,
        "\ndefine {f} @\"{f}\"(",
        .{ okc.Typ.LLPrinter{ .typ = fun_typ.ret_typ.* }, name },
    );
    var param_typ_vals = try ctx.gpa.alloc(
        okc.Val.Typed,
        self.header.params.len + self.header.context.len,
    );
    defer ctx.gpa.free(param_typ_vals);
    if (self.header.params.len != 0) {
        param_typ_vals[0] = try Param.gen(fun_typ.params[0], ctx);
        for (param_typ_vals[1..fun_typ.params.len], fun_typ.params[1..]) |*target, param_typ| {
            try ctx.extra_buffer.appendSlice(ctx.gpa, ", ");
            target.* = try Param.gen(param_typ, ctx);
        }
    }
    if (self.header.context.len != 0) {
        if (self.header.params.len != 0) {
            try ctx.extra_buffer.appendSlice(ctx.gpa, ", ");
        }
        param_typ_vals[self.header.params.len] = try Param.gen(fun_typ.context[0].typ, ctx);
        for (
            param_typ_vals[self.header.params.len + 1 ..],
            fun_typ.context[1..],
        ) |*target, param| {
            try ctx.extra_buffer.appendSlice(ctx.gpa, ", ");
            target.* = try Param.gen(param.typ, ctx);
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
    for (
        param_typ_vals[self.header.params.len..],
        self.header.context,
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

pub fn check(self: @This(), location: okc.Location, generics_usage: std.bit_set.Dynamic, ctx: okc.Item.Check) !void {
    std.log.debug("check fun in {f}\n", .{location});
    var stmt_check = ctx.stmtCheckCtx(self.header);
    defer stmt_check.deinit();
    try okc.Item.regGenerics(self.header.generics, generics_usage, &stmt_check);
    for (self.header.params) |param| {
        try stmt_check.declare(param.name, param.location, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        });
    }
    for (self.header.context) |param| {
        try stmt_check.declare(param.name, param.location, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        });
    }
    const control_flow = try self.body.check(&stmt_check);
    if (@backingInt(control_flow) < @backingInt(okc.ControlFlow.ret) and
        !self.header.ret_typ.isVoid() and
        self.header.ret_typ != .never)
    {
        ctx.failer.fail(location, "function may not return", .{});
    }
    if (self.header.ret_typ == .never and control_flow != .never) {
        ctx.failer.fail(location, "function may return", .{});
    }
    stmt_check.freeVars(0);
}

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
