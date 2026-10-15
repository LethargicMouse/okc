const std = @import("std");

pub const Binary = @import("Binary.zig");
const Item = @import("../Item.zig");
const Location = @import("../Location.zig");
const Module = @import("../Module.zig");
const Typ = @import("../typ/mod.zig").Typ;
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
        header: Item.Fun.Header,
        location: Location,
        fun_arena: *std.heap.ArenaAllocator,
        solve_queue: *std.ArrayList(Typ.SolveReq),
    ) !Info {
        var resolve_map: std.StringHashMap(Typ) = .init(fun_arena.child_allocator);
        defer resolve_map.deinit();
        self.generics = try Typ.Lazy.makeGenerics(Module.arena, fun_arena, header.generics.len);
        for (header.generics, self.generics) |generic, typ| {
            try resolve_map.put(generic.name, typ);
        }
        const params = try Module.arena.alloc(Typ, header.params.len);
        defer Module.arena.free(params);
        for (header.params, params) |param, *target| {
            target.* = try param.typ.resolve(resolve_map);
        }
        for (self.generics, header.generics) |*target, generic| {
            target.* = resolve_map.get(generic.name).?;
            try solve_queue.append(fun_arena.child_allocator, .{
                .typ = target,
                .location = null,
            });
        }
        const ret_typ = try header.ret_typ.resolve(resolve_map);
        self.typ = .{ .fun = .{
            .params = try Typ.memo.save(params),
            .ret_typ = try Typ.memo.box(ret_typ),
        } };
        try solve_queue.append(fun_arena.child_allocator, .{
            .typ = &self.typ,
            .location = location,
        });
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
    typ: Typ = .any,
};

// lol
pub const Undef = struct {
    typ: Typ = .any,
};

pub const Call = struct {
    expr: Expr,
    args: []Expr,
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
