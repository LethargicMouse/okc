const std = @import("std");

const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,
context: Context,

pub const Context = @import("Call/Context.zig");
pub const Info = @import("Call/Info.zig");
pub const Postfix = @import("Call/Postfix.zig");

pub fn parsePostfix(ctx: *okc.Parser) !okc.Expr.Postfix {
    const call: Postfix = try .parse(ctx);
    return .{
        .location = ctx.tmp_location,
        .kind = .{ .call = call },
    };
}

pub fn check(self: *@This(), hint: okc.Typ, ctx: okc.Expr.Check) !okc.Expr.Info {
    const callee = try self.expr.check(.{}, ctx);
    const info: Info = .{
        .args = self.args,
        .context = self.context,
        .location = self.expr.location,
        .maybe_first = null,
        .typ = callee.typ,
    };
    return info.check(hint, ctx);
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const callee = try self.expr.gen(ctx);
    return genWithVal(callee, null, self.args, self.context, ctx);
}

pub fn genWithVal(
    callee: okc.Val.Typed,
    first: ?okc.Val.Typed,
    args: []const okc.Expr,
    context: Context,
    ctx: *okc.Codegen,
) !okc.Val.Typed {
    var arg_typ_vals = try ctx.gpa.alloc(
        okc.Val.Typed,
        args.len +
            callee.typ.fun.context.len +
            @intFromBool(first != null),
    );
    defer ctx.gpa.free(arg_typ_vals);
    var arg_typ_vals_to_fill = arg_typ_vals;
    var params = callee.typ.fun.params;
    if (first) |val| {
        arg_typ_vals[0] = val;
        arg_typ_vals_to_fill = arg_typ_vals[1..];
        params = params[1..];
    }
    for (arg_typ_vals_to_fill[0..args.len], args, params) |*target, arg, param| {
        target.* = try arg.gen(ctx);
        if (param == .slice and target.typ == .ptr) {
            target.* = try okc.Expr.Array.castToSlice(target.typ.ptr.typ.array, target.bare, ctx);
        }
    }
    for (
        arg_typ_vals[args.len + @intFromBool(first != null) ..],
        callee.typ.fun.context,
    ) |*target, param| {
        for (context.fields) |field| {
            if (std.mem.eql(u8, field.name, param.name)) {
                target.* = try field.expr.gen(ctx);
                break;
            }
        } else for (ctx.context) |outer| {
            if (std.mem.eql(u8, outer.name, param.name)) {
                target.* = try ctx.vars.get(outer.name).?.loadTypVal(ctx);
                break;
            }
        } else {
            unreachable;
        }
    }
    const ret_tmp = ctx.counter.next();
    if (callee.typ.fun.ret_typ.isVoid() or callee.typ.fun.ret_typ.* == .never) {
        try ctx.buffer.print(ctx.gpa, "\n  ", .{});
    } else {
        try ctx.buffer.print(ctx.gpa, "\n  %t{} = ", .{ret_tmp});
    }
    try ctx.buffer.print(ctx.gpa, "call {f} {f} (", .{
        okc.Typ.LLPrinter{ .typ = callee.typ.fun.ret_typ.* },
        callee.bare,
    });
    if (arg_typ_vals.len != 0) {
        try ctx.buffer.print(ctx.gpa, "{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try ctx.buffer.print(ctx.gpa, ", {f}", .{val});
        }
    }
    try ctx.buffer.print(ctx.gpa, ")", .{});
    return .{
        .typ = callee.typ.fun.ret_typ.*,
        .bare = .{ .tmp = ret_tmp },
    };
}
