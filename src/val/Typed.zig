const std = @import("std");

const okc = @import("okc");

bare: okc.Val,
typ: okc.Typ,

pub fn genIV(self: *@This(), val: @This(), index: u64, ctx: *okc.Codegen) !void {
    const tmp = ctx.newTmp();
    try ctx.buffer.?.print(
        ctx.gpa,
        "\n  %t{} = insertvalue {f}, {f}, {d}",
        .{ tmp, self, val, index },
    );
    self.bare = .{ .tmp = tmp };
}

pub fn genCall(
    self: @This(),
    first: ?okc.Val.Typed,
    args: []const okc.Expr,
    ctx: *okc.Codegen,
) !@This() {
    var arg_typ_vals = try ctx.gpa.alloc(okc.Val.Typed, args.len + @intFromBool(first != null));
    defer ctx.gpa.free(arg_typ_vals);
    var arg_typ_vals_to_fill = arg_typ_vals;
    var params = self.typ.fun.params;
    if (first) |val| {
        arg_typ_vals[0] = val;
        arg_typ_vals_to_fill = arg_typ_vals[1..];
        params = params[1..];
    }
    for (arg_typ_vals_to_fill, args, params) |*target, arg, param| {
        target.* = try arg.gen(ctx);
        if (param == .slice and target.typ == .ptr) {
            target.* = try ctx.genArrayToSlice(target.typ.ptr.typ.array, target.bare);
        }
    }
    const ret_tmp = ctx.newTmp();
    if (self.typ.fun.ret_typ.* != .prime or self.typ.fun.ret_typ.prime != .void) {
        try ctx.buffer.?.print(ctx.gpa, "\n  %t{} = ", .{ret_tmp});
    } else {
        try ctx.buffer.?.print(ctx.gpa, "\n  ", .{});
    }
    try ctx.buffer.?.print(ctx.gpa, "call {f} {f} (", .{
        okc.Typ.LLPrinter{ .typ = self.typ.fun.ret_typ.* },
        self.bare,
    });
    if (args.len != 0) {
        try ctx.buffer.?.print(ctx.gpa, "{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try ctx.buffer.?.print(ctx.gpa, ", {f}", .{val});
        }
    }
    try ctx.buffer.?.print(ctx.gpa, ")", .{});
    return .{
        .typ = self.typ.fun.ret_typ.*,
        .bare = .{ .tmp = ret_tmp },
    };
}

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("{f} {f}", .{ okc.Typ.LLPrinter{ .typ = self.typ }, self.bare });
}

pub fn int(n: u64) okc.Val.Typed {
    return .{
        .typ = .{ .prime = .i32 },
        .bare = .{ .int = n },
    };
}
