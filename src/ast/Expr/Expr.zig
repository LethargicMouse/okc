const Location = @import("../../Location.zig");
const Typ = @import("../../typ/mod.zig").Typ;
pub const Binary = @import("Binary.zig");
pub const Unary = @import("Unary.zig");

const Self = @This();

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

pub const Method = struct {
    expr: Self,
    vari: Var,
    args: []Self,
    name_location: Location,
};

pub const FunMeta = struct {
    generics: []Typ,
    typ: Typ,
};

pub const Subslice = struct {
    expr: Self,
    start: Self,
    end: Self,
};

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Self,
    typ: Typ = .any,
};

pub const Struct = struct {
    fields: []Struct.Field,
    typ: Typ = .any,

    pub const Field = struct {
        name: []const u8,
        expr: Self,
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
    expr: Self,
    args: []Self,
};

pub const Field = struct {
    expr: Self,
    name: []const u8,
};

pub const Elem = struct {
    expr: Self,
    index: Self,
};
