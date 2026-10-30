const okc = @import("okc");

expr: okc.Expr,
args: []okc.Expr,
context: Context,

pub const Context = @import("Call/Context.zig");
pub const Postfix = @import("Call/Postfix.zig");

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
    const ret_tmp = ctx.counter.next();
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
