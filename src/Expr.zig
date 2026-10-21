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
pub const Member = @import("Expr/Member.zig");
pub const Method = @import("Expr/Method.zig");
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

pub fn parseAtom(
    ctx: *okc.Parser,
    mode: okc.Parser.Mode,
) error{ ParseFailed, OutOfMemory }!okc.Expr {
    return ctx.either(.{
        okc.Parser.parseAtExpr,
        Member.parseExpr,
        okc.Parser.parseParExpr,
        okc.Parser.parseArrayExpr,
        okc.Parser.parseUnaryExpr,
        okc.Parser.parseInferStructExpr,
        okc.Parser.parseStructExpr,
        okc.Parser.parseIntExpr,
        okc.Parser.parseStrExpr,
        okc.Parser.parseCharExpr,
        okc.Parser.parseVarExpr,
        okc.Parser.parseUndefinedExpr,
        okc.Parser.parseTrueExpr,
        okc.Parser.parseFalseExpr,
    }) catch |err| {
        if (mode == .loud) {
            try ctx.fail("<expr>");
        }
        return err;
    };
}

pub fn genRef(self: @This(), ctx: *okc.Codegen) error{ WriteFailed, OutOfMemory }!okc.Val.Ref {
    switch (self.kind) {
        .member => unreachable,
        .vari => |vari| return vari.genRef(ctx),
        .field => |field| return field.genRef(ctx),
        .elem => |elem| return ctx.genElemExprRef(elem.*),
        .deref => |deref| return ctx.genDerefRef(deref.expr),
        .subslice,
        .sizeof,
        .call,
        .method,
        .binary,
        .named_struc,
        .int,
        .str,
        .char,
        .undef,
        .bool,
        .struc,
        .array,
        .ptr,
        .neg,
        .notb,
        => {
            const typ_val = try self.gen(ctx);
            return ctx.toStack(typ_val);
        },
    }
}

pub fn gen(self: @This(), ctx: *okc.Codegen) error{ OutOfMemory, WriteFailed }!okc.Val.Typed {
    switch (self.kind) {
        .member => unreachable,
        .method => |method| return method.gen(ctx),
        .deref => |deref| return ctx.genDeref(deref.expr),
        .neg => |neg| return ctx.genNeg(neg.expr),
        .notb => |notb| return ctx.genNotb(notb.expr),
        .ptr => |ptr| return ctx.genPtr(ptr.expr),
        .subslice => |subslice| return ctx.genSubslice(subslice.*),
        .sizeof => |typ| return ctx.genSizeof(typ),
        .array => |array| return ctx.genArray(array),
        .struc => |struc| return ctx.genStructExpr(struc),
        .int => |int| return okc.Codegen.genInt(int),
        .str => |str| return ctx.genStr(str.bare),
        .vari => |vari| return vari.gen(ctx),
        .char => |char| return okc.Codegen.genChar(char),
        .bool => |boo| return okc.Codegen.genBool(boo),
        .undef => |undef| return okc.Codegen.genUndef(undef),
        .call => |call| return call.gen(ctx),
        .binary => |binary| return ctx.genBinaryExpr(binary.*),
        .field => |field| return field.gen(ctx),
        .named_struc => |struc| return ctx.genNamedStructExpr(struc),
        .elem => |elem| return ctx.genElem(elem.*),
    }
}

pub fn genConst(self: @This(), ctx: *okc.Codegen) error{ OutOfMemory, WriteFailed }!okc.Typ {
    switch (self.kind) {
        .str => |str| return str.genConst(ctx),
        .named_struc => |struc| return struc.bare.genConst(ctx),
        .struc => |struc| return struc.genConst(ctx),
        .array => |array| return array.genConst(ctx),
        else => unreachable,
    }
}

pub fn genConstField(self: @This(), index: usize, ctx: *okc.Codegen) !okc.Typ {
    switch (self.kind) {
        .field => |field| {
            // it is enum
            std.debug.assert(index == 0);
            const name = field.expr.kind.vari.name;
            const variant_index = ctx.typ_decls.get(.{ .name = name }).?.variants.get(field.vari.name).?;
            try ctx.buffer.?.print(ctx.gpa, "i32 {}", .{variant_index});
            return .{ .prime = .i32 };
        },
        else => unreachable,
    }
}

fn checkComptime(self: @This(), failer: *okc.Failer) void {
    switch (self.kind) {
        .member => unreachable,
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
        .member => unreachable,
        .method => |method| return method.check(hint.typ, ctx),
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
        .vari => |*vari| return vari.check(
            self.location,
            if (hint.mutable) .mutable else .constant,
            ctx,
        ),
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

pub const Hint = struct {
    typ: okc.Typ = .any,
    mutable: bool = false,
};

pub const Check = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    mod_typ: okc.Typ.Name,
    items: std.StringHashMap(okc.Item.Info),
    modules: std.StringHashMap(okc.Module.Info),
    failer: *okc.Failer,

    pub fn inside(self: @This(), typ: okc.Typ) ?@This() {
        var res = self;
        const name = typ.getName() orelse return null;
        res.mod_typ = name;
        res.items = name.getItems(self.items) orelse return null;
        return res;
    }
};
