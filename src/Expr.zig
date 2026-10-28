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
        okc.Parser.parseSizeofExpr,
        Member.parseExpr,
        okc.Parser.parseParExpr,
        Array.parseExpr,
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
        .i_array => unreachable,
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
    return switch (self.kind) {
        .i_array => |array| array.gen(ctx),
        .member => |member| member.gen(ctx),
        .method => |method| method.gen(ctx),
        .deref => |deref| ctx.genDeref(deref.expr),
        .neg => |neg| ctx.genNeg(neg.expr),
        .notb => |notb| ctx.genNotb(notb.expr),
        .ptr => |ptr| ctx.genPtr(ptr.expr),
        .subslice => |subslice| ctx.genSubslice(subslice.*),
        .sizeof => |typ| ctx.genSizeof(typ),
        .array => |array| array.gen(ctx),
        .struc => |struc| ctx.genStructExpr(struc),
        .int => |int| okc.Codegen.genInt(int),
        .str => |str| ctx.genStr(str.bare),
        .vari => |vari| vari.gen(ctx),
        .char => |char| okc.Codegen.genChar(char),
        .bool => |boo| okc.Codegen.genBool(boo),
        .undef => |undef| okc.Codegen.genUndef(undef),
        .call => |call| call.gen(ctx),
        .binary => |binary| ctx.genBinaryExpr(binary.*),
        .field => |field| field.gen(ctx),
        .named_struc => |struc| ctx.genNamedStructExpr(struc),
        .elem => |elem| ctx.genElem(elem.*),
    };
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

pub fn genInt(self: @This(), ctx: *okc.Codegen) !u64 {
    switch (self.kind) {
        .field => |field| {
            // it is enum
            const name = field.expr.kind.vari.name;
            return ctx.typ_decls.get(.{ .name = name }).?
                .variants.get(field.vari.name).?;
        },
        .member => |member| {
            // it is enum
            const name = member.typ.name;
            return ctx.typ_decls.get(.{ .name = name }).?
                .variants.get(member.vari.name).?;
        },
        else => unreachable,
    }
}

fn checkComptime(self: @This(), failer: *okc.Failer) void {
    switch (self.kind) {
        .i_array => unreachable,
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
    return switch (self.kind) {
        .i_array => |*array| array.check(hint.typ, self.location, ctx),
        .member => |*member| member.check(
            self.location,
            hint.typ,
            if (hint.mutable) .mutable else .constant,
            ctx,
        ),
        .method => |method| method.check(hint.typ, ctx),
        .deref => |deref| deref.check(self.location, ctx),
        .neg => |neg| neg.check(ctx),
        .notb => |notb| notb.check(ctx),
        .ptr => |ptr| ptr.check(hint.typ, ctx),
        .subslice => |subslice| subslice.check(self.location, ctx),
        .sizeof => |typ| Sizeof.check(typ),
        .array => |*array| array.check(hint.typ, ctx),
        .struc => |*struc| struc.check(self.location, hint.typ, ctx),
        .int => |*int| int.check(),
        .str => Str.check(ctx.arena),
        .vari => |*vari| vari.check(
            self.location,
            if (hint.mutable) .mutable else .constant,
            ctx,
        ),
        .char => .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |*undef| undef.check(hint.typ, ctx.arena),
        .call => |call| call.check(hint.typ, ctx),
        .binary => |binary| binary.check(ctx),
        .field => |field| field.check(self.location, hint.mutable, ctx),
        .named_struc => |*struc| struc.check(self.location, ctx),
        .elem => |elem| elem.check(self.location, ctx),
    };
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
