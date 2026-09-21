const Lexeme = @import("../Lexer.zig").Lexeme;
const Location = @import("../Location.zig");
const Typ = @import("typ.zig").Typ;

const Expr = @This();

location: Location,
kind: Kind,

pub const Kind = union(enum) {
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

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Expr,
    typ: Typ = undefined,
};

pub const Unary = struct {
    pub const Kind = enum {
        ptr,
        deref,
        notb,
        neg,

        pub fn fromLexeme(lexeme: Lexeme) ?Unary.Kind {
            return switch (lexeme) {
                .amp => .ptr,
                .star => .deref,
                .tild => .notb,
                .minus => .neg,
                else => null,
            };
        }
    };
    kind: Unary.Kind,
    expr: Expr,
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
    ret_typ: Typ = undefined,
};

pub const Binary = struct {
    pub const Kind = enum {
        pub const Class = enum {
            arith,
            bool,
        };

        orb,
        andb,
        equ,
        add,
        sub,
        mul,
        div,
        les,
        rem,
        moreq,

        pub fn getPrior(kind: Binary.Kind) u8 {
            switch (kind) {
                .equ, .les, .moreq => return 0,
                .orb => return 1,
                .andb => return 2,
                .add, .sub => return 3,
                .mul, .div, .rem => return 4,
            }
        }

        pub fn fromLexeme(lexeme: Lexeme) ?Binary.Kind {
            return switch (lexeme) {
                .pipe => .orb,
                .amp => .andb,
                .equ2 => .equ,
                .plus => .add,
                .minus => .sub,
                .star => .mul,
                .slash => .div,
                .les => .les,
                .rem => .rem,
                .moreq => .moreq,
                else => null,
            };
        }

        pub fn getClass(kind: Binary.Kind) Class {
            return switch (kind) {
                .orb, .andb, .add, .sub, .mul, .div, .rem => .arith,
                .equ, .les, .moreq => .bool,
            };
        }
    };

    left: Expr,
    kind: Binary.Kind,
    right: Expr,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
    typ: Typ = undefined,
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
};
