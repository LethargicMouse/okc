const std = @import("std");

pub const Binary = @import("Binary.zig");
const Checker = @import("../Checker.zig");
const Failer = @import("../Failer.zig");
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

    pub const Field = struct {
        name: []const u8,
        expr: Expr,
        location: Location,
    };

    pub const Named = struct {
        name: []const u8,
        struc: Struct,
    };
};

pub const Int = struct {
    val: u64,
    typ: Typ = .int,
};

// lol
pub const Undef = struct {
    typ: Typ = .any,
};

pub const Call = struct {
    expr: Expr,
    args: []Expr,

    pub fn check(self: *@This(), hint: Typ, failer: *Failer, checker: *Checker) !Expr.Info {
        const callee_info = try checker.checkExpr(&self.expr, .{});
        const fun = callee_info.typ.getFun(self.expr.location, failer) orelse
            return self.checkBad(checker);
        // to propagate hint to generics
        _ = fun.ret_typ.unify(hint, .active);
        for (self.args, fun.params) |*arg, param| {
            const info = try checker.checkExpr(arg, .{ .typ = param.normalise() });
            _ = checker.unify(arg.location, param, info.typ);
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
