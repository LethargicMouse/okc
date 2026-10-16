const std = @import("std");

const okc = @import("okc");

pub const Array = @import("Expr/Array.zig");
pub const Binary = @import("Expr/Binary.zig");
pub const Call = @import("Expr/Call.zig");
pub const Deref = @import("Expr/Deref.zig");
pub const Elem = @import("Expr/Elem.zig");
pub const Field = @import("Expr/Field.zig");
pub const FunMeta = @import("Expr/FunMeta.zig");
pub const Info = @import("Expr/Info.zig");
pub const Int = @import("Expr/Int.zig");
pub const Kind = @import("Expr/kind.zig").Kind;
pub const Neg = @import("Expr/Neg.zig");
pub const Notb = @import("Expr/Notb.zig");
pub const Ptr = @import("Expr/Ptr.zig");
pub const Sizeof = @import("Expr/Sizeof.zig");
pub const Str = @import("Expr/Str.zig");
pub const Struct = @import("Expr/Struct.zig");
pub const Subslice = @import("Expr/Subslice.zig");
pub const Unary = @import("Expr/unary.zig").Unary;
pub const Undef = @import("Expr/Undef.zig");
pub const Var = @import("Expr/Var.zig");

location: okc.Location,
kind: Kind,

fn checkComptime(self: @This(), failer: *okc.Failer) void {
    switch (self.kind) {
        .str, .bool, .char, .int, .sizeof, .vari, .undef => {},
        .call, .method => failer.fail(self.location, "cannot evaluate at compile time", .{}),
        .deref => |deref| deref.expr.checkComptime(failer),
        .neg => |neg| neg.expr.checkComptime(failer),
        .notb => |notb| notb.expr.checkComptime(failer),
        .ptr => |ptr| ptr.expr.checkComptime(failer),
        .field => |field| field.expr.checkComptime(failer),
        .elem => |elem| {
            elem.expr.checkComptime(failer);
            elem.index.checkComptime(failer);
        },
        .binary => |binary| {
            binary.left.checkComptime(failer);
            binary.right.checkComptime(failer);
        },
        .subslice => |subslice| {
            subslice.expr.checkComptime(failer);
            subslice.start.checkComptime(failer);
            subslice.end.checkComptime(failer);
        },
        .array => |array| for (array.exprs) |expr| {
            expr.checkComptime(failer);
        },
        .named_struc => |named| for (named.bare.fields) |field| {
            field.expr.checkComptime(failer);
        },
        .struc => |struc| for (struc.fields) |field| {
            field.expr.checkComptime(failer);
        },
    }
}

pub fn checkConst(self: *@This(), hint: okc.Expr.Hint, ctx: Check) !okc.Typ {
    const info = try self.check(hint, ctx);
    self.checkComptime(ctx.failer);
    return info.typ;
}

pub fn check(self: *@This(), hint: okc.Expr.Hint, ctx: Check) error{OutOfMemory}!okc.Expr.Info {
    switch (self.kind) {
        .method => unreachable,
        .deref => |deref| return deref.check(self.location, ctx),
        .neg => |neg| return neg.check(ctx),
        .notb => |notb| return notb.check(ctx),
        .ptr => |ptr| return ptr.check(hint.typ, ctx),
        .subslice => |subslice| return subslice.check(self.location, ctx),
        .sizeof => |typ| return Sizeof.check(typ),
        .array => |*array| return array.check(hint.typ, ctx),
        .struc => |*struc| return struc.check(self.location, hint.typ, ctx),
        .int => |*int| return int.check(),
        .str => return Str.check(ctx.arena),
        .vari => |*vari| return vari.check(self.location, hint.mutable, ctx),
        .char => return .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => return .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |*undef| return undef.check(hint.typ, ctx.arena),
        .call => |call| return call.check(hint.typ, ctx),
        .binary => |binary| return binary.check(ctx),
        .field => |field| return field.check(self.location, hint.mutable, ctx),
        .named_struc => |*struc| return struc.check(self.location, ctx),
        .elem => |elem| return elem.check(self.location, ctx),
    }
}

pub const Method = struct {
    expr: okc.Expr,
    vari: Var,
    args: []okc.Expr,
    name_location: okc.Location,
};

pub const Hint = struct {
    typ: okc.Typ = .any,
    mutable: bool = false,
};

pub const Check = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    items: std.StringHashMap(okc.Item.Info),
    failer: *okc.Failer,
};
