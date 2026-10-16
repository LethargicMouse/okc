const std = @import("std");

pub const Binary = @import("Binary.zig");
const Checker = @import("../Checker.zig");
const fail = @import("../fail.zig");
const Item = @import("../Item.zig");
const Location = @import("../Location.zig");
const Module = @import("../Module.zig");
const Typ = @import("../typ/typ.zig").Typ;
pub const Unary = @import("Unary.zig");

location: Location,
kind: Kind,

pub const Kind = union(enum) {
    array: Array,
    binary: *Binary,
    bool: bool,
    call: *Call,
    char: u8,
    elem: *Elem,
    field: *Field,
    int: Int,
    method: *Method,
    named_struc: Struct.Named,
    sizeof: Typ,
    str: []const u8,
    struc: Struct,
    subslice: *Subslice,
    unary: *Unary,
    undef: Undef,
    vari: Var,
};

pub const Var = struct {
    name: []const u8,
    fun_meta: ?FunMeta = null,

    pub fn check(
        self: *@This(),
        gpa: std.mem.Allocator,
        location: Location,
        hint_mutable: bool,
        items: std.StringHashMap(Item.Info),
    ) !Expr.Info {
        const err = Expr.Info{
            .typ = .err,
            .mutable = true,
        };
        const item = items.getPtr(self.name) orelse {
            fail.notDeclared(location, self.name);
            return err;
        };
        switch (item.kind) {
            .fun => |header| {
                item.used = true;
                self.fun_meta = @as(Expr.FunMeta, undefined);
                return self.fun_meta.?.fillFromHeader(gpa, header.*);
            },
            .struc, .typ => {
                fail.fail(location, "it is a type", .{});
                return err;
            },
            .vari => |*vari_decl| {
                item.used = true;
                if (hint_mutable) {
                    if (vari_decl.mutable) {
                        vari_decl.mutated = true;
                    } else {
                        if (vari_decl.can_be_mutable) {
                            std.log.info("add `mut` before name in {f}", .{item.location});
                        }
                    }
                }
                return .{
                    .typ = vari_decl.typ,
                    .mutable = vari_decl.mutable,
                };
            },
        }
    }
};

const Expr = @This();

pub const Method = struct {
    expr: Expr,
    vari: Var,
    args: []Expr,
    name_location: Location,
};

pub const FunMeta = struct {
    generics: []Typ,
    typ: Typ,

    pub fn fillFromHeader(
        self: *@This(),
        gpa: std.mem.Allocator,
        header: Item.Fun.Header,
    ) !Info {
        var resolve_map: std.StringHashMap(Typ) = .init(gpa);
        defer resolve_map.deinit();
        self.generics = try Module.arena.alloc(Typ, header.generics.len);
        @memset(self.generics, .any);
        for (header.generics, self.generics) |generic, *typ| {
            try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
        }
        const params = try gpa.alloc(Typ, header.params.len);
        defer gpa.free(params);
        for (header.params, params) |param, *target| {
            target.* = try param.typ.resolve(resolve_map);
        }
        const ret_typ = try header.ret_typ.resolve(resolve_map);
        self.typ = .{ .fun = .{
            .params = try Typ.memo.save(params),
            .ret_typ = try Typ.memo.box(ret_typ),
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }
};

pub const Subslice = struct {
    expr: Expr,
    start: Expr,
    end: Expr,
};

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Expr,
    typ: Typ = .any,
};

pub const Struct = struct {
    fields: []Struct.Field,
    typ: Typ = .any,

    pub fn checkTyped(
        self: *@This(),
        name: Typ.Name,
        location: Location,
        ctx: Item.ResolveCtx,
        checker: *Checker,
    ) !Expr.Info {
        const err = Expr.Info{
            .typ = .err,
            .mutable = false,
        };
        const item = ctx.items.getPtr(name.name) orelse {
            fail.notDeclared(location, name.name);
            return err;
        };
        item.used = true;
        const decl = if (item.kind == .struc) item.kind.struc else {
            fail.notStruct(location, .{ .name = name });
            return err;
        };
        const generics = try ctx.gpa.alloc(Typ, decl.generics.len);
        defer ctx.gpa.free(generics);
        if (name.generics.len == 0) {
            @memset(generics, .any);
        } else {
            @memcpy(generics, name.generics);
        }
        var resolve_map: std.StringHashMap(Typ) = .init(ctx.gpa);
        defer resolve_map.deinit();
        for (decl.generics, generics) |generic, *typ| {
            try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
        }
        for (self.fields) |*field| {
            try checker.checkNewField(field, .{ .name = name }, decl.fields, resolve_map);
        }
        Checker.checkFieldsInitialised(decl.fields, self.fields, location);
        self.typ = Typ{ .name = .{
            .generics = try Typ.memo.save(generics),
            .name = name.name,
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }

    pub const Field = struct {
        name: []const u8,
        expr: Expr,
        location: Location,
    };

    pub const Named = struct {
        name: []const u8,
        struc: Struct,

        pub fn check(
            self: *@This(),
            location: Location,
            ctx: Item.ResolveCtx,
            checker: *Checker,
        ) !Expr.Info {
            return self.struc.checkTyped(.{ .name = self.name }, location, ctx, checker);
        }
    };
};

pub const Int = struct {
    val: u64,
    typ: Typ = .int,

    pub fn check(self: *@This()) !Info {
        std.debug.assert(self.typ == .int);
        return .{
            .typ = .{ .lazy = .from(&self.typ) },
            .mutable = false,
        };
    }
};

// lol
pub const Undef = struct {
    typ: Typ = .any,

    pub fn check(self: *@This(), typ: Typ) !Info {
        self.typ = typ;
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }
};

pub const Call = struct {
    expr: Expr,
    args: []Expr,

    pub fn check(self: *@This(), hint: Typ, checker: *Checker) !Expr.Info {
        const callee_info = try checker.checkExpr(&self.expr, .{});
        const fun = callee_info.typ.getFun(self.expr.location) orelse
            return self.checkBad(checker);
        // to propagate hint to generics
        _ = fun.ret_typ.unify(hint, .active);
        for (self.args, fun.params) |*arg, param| {
            const info = try checker.checkExpr(arg, .{ .typ = param.normalise() });
            _ = Checker.unify(arg.location, param, info.typ);
        }
        return .{
            .typ = fun.ret_typ.*,
            .mutable = false,
        };
    }

    fn checkBad(call: *@This(), checker: *Checker) !Info {
        for (call.args) |*arg| {
            _ = try checker.checkExpr(arg, .{});
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    }
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,

    pub fn check(
        self: *@This(),
        location: Location,
        hint_mutable: bool,
        ctx: struct {
            gpa: std.mem.Allocator,
            items: std.StringHashMap(Item.Info),
        },
        checker: *Checker,
    ) !Expr.Info {
        var info = try checker.checkExpr(&self.expr, .{ .mutable = hint_mutable });
        const err = Expr.Info{
            .typ = .err,
            .mutable = true,
        };
        var norm = info.typ.normalise();
        if (norm == .ptr) {
            info.mutable = norm.ptr.mutable;
            norm = norm.ptr.typ.normalise();
        }
        if (norm == .slice) {
            return norm.slice.checkField(info.mutable, self.name, location);
        }
        const name = norm.getStructName(self.expr.location) orelse return err;
        const item = ctx.items.get(name.name) orelse {
            fail.notStruct(self.expr.location, norm);
            return err;
        };
        const struc = if (item.kind == .struc) item.kind.struc else {
            fail.notStruct(self.expr.location, norm);
            return err;
        };
        const fiel = struc.fields.getPtr(self.name) orelse {
            fail.noField(location, self.name, .{ .name = name });
            return err;
        };
        fiel.used = true;
        var resolve_map: std.StringHashMap(Typ) = .init(ctx.gpa);
        defer resolve_map.deinit();
        for (struc.generics, name.generics) |generic, typ| {
            try resolve_map.put(generic.name, typ);
        }
        return .{
            .typ = try fiel.typ.resolve(resolve_map),
            .mutable = info.mutable,
        };
    }
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
};

pub const Info = struct {
    typ: Typ,
    mutable: bool,
};

pub const Hint = struct {
    typ: Typ = .any,
    mutable: bool = false,
};
