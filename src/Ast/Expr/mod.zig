const Lexeme = @import("../../Lexer.zig").Lexeme;
const Location = @import("../../Location.zig");
pub const Binary = @import("Binary.zig");
pub const Unary = @import("Unary.zig");
const Typ = @import("../../typ.zig").Typ;

const Self = @This();

location: Location,
kind: Kind,

pub const Kind = union(enum) {
    method: *Method,
    subslice: *Subslice,
    sizeof: Typ,
    array: Array,
    unary: *Unary,
    struc: Struct,
    named_struc: Struct.Named,
    int: Int,
    str: []const u8,
    vari: Var,
    char: u8,
    undef: Undef,
    bool: bool,
    call: *Call,
    binary: *Binary,
    field: *Field,
    elem: *Elem,
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
    generics: []const Typ = undefined,
    fun: Typ.Fun = undefined,
};

pub const Subslice = struct {
    expr: Self,
    start: Self,
    end: Self,
};

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Self,
    typ: Typ = undefined,
};

pub const Struct = struct {
    fields: []Struct.Field,
    typ: Typ = undefined,

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
    typ: Typ = undefined,
};

// lol
pub const Undef = struct {
    typ: Typ = undefined,
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
