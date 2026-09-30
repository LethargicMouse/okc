const Lexeme = @import("../Lexer.zig").Lexeme;
const Location = @import("../Location.zig");
pub const Binary = @import("Expr/Binary.zig");
pub const Unary = @import("Expr/Unary.zig");
const Typ = @import("typ.zig").Typ;

const Expr = @This();

location: Location,
kind: Kind,

pub const Kind = union(enum) {
    subslice: *Subslice,
    sizeof: Typ,
    array: Array,
    unary: *Unary,
    struc: Struct,
    named_struc: Struct.Named,
    int: Int,
    str: []const u8,
    vari: []const u8,
    fn_ptr: []const u8,
    char: u8,
    undef: Undef,
    bool: bool,
    call: Call,
    binary: *Binary,
    field: *Field,
    elem: *Elem,
};

pub const Subslice = struct {
    expr: Expr,
    start: Expr,
    end: Expr,
};

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Expr,
    typ: Typ = undefined,
};

pub const Struct = struct {
    fields: []Struct.Field,
    typ: Typ = undefined,

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
    typ: Typ = undefined,
};

// lol
pub const Undef = struct {
    typ: Typ = undefined,
};

pub const Call = struct {
    name: []const u8,
    args: []Expr,
    generics: []Typ = undefined,
    params: []Typ = undefined,
    ret_typ: Typ = undefined,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
};
