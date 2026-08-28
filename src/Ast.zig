const std = @import("std");

const builtin = @import("builtin");

const Location = @import("Location.zig");

pub const ExtFun = struct {
    header: Header,
};

pub const Header = struct {
    name: []const u8,
    params: []const Param,
    ret_typ: Typ,
    location: Location,
};

pub const Param = struct {
    name: []const u8,
    typ: Typ,
    location: Location,
};

pub const Typ = union(enum) {
    pub const Array = struct {
        len: []const u8,
        typ: Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
    };

    prime: Prime,
    name: Name,
    ptr: *const Typ,
    mut_ptr: *const Typ,
    array: *const Array,

    pub fn fromName(name: []const u8) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = .{ .name = name } };
    }

    pub fn isVoid(typ: Typ) bool {
        return typ == .prime and typ.prime == .void;
    }
};

pub const Prime = enum {
    u8,
    i32,
    u32,
    u64,
    bool,
    void,

    pub fn isNumber(prime: Prime) bool {
        switch (prime) {
            .i32, .u8, .u32, .u64 => return true,
            .bool, .void => return false,
        }
    }
};

const Block = []const Statement;

pub const Fun = struct {
    header: Header,
    body: Block,
};

pub const OpAssign = struct {
    left: Expr,
    kind: Binary.Kind,
    right: Expr,
};

pub const Statement = struct {
    pub const Kind = union(enum) {
        ret: Return,
        expr: Expr,
        declare: Declare,
        assign: Assign,
        op_assign: OpAssign,
        iff: If,
        whi: While,
        ignore: Ignore,
        mut_declare: Declare,
        brek,
        unre,
    };
    location: Location,
    kind: Kind,
};

pub const Ignore = struct {
    expr: Expr,
};

pub const Return = struct {
    expr: ?Expr,
};

pub const While = struct {
    branch: Branch,
};

pub const If = struct {
    branch: Branch,
    else_ifs: []const Branch,
    else_branch: []const Statement,
};

pub const Branch = struct {
    condition: Expr,
    body: []const Statement,
};

pub const Assign = struct {
    left: Expr,
    expr: Expr,
};

pub const Declare = struct {
    name: []const u8,
    typ: ?Typ,
    expr: Expr,
};

pub const Call = struct {
    name: []const u8,
    args: []const Expr,
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,
};

pub const Unary = struct {
    pub const Kind = enum {
        mut_ptr,
        ptr,
        deref,
        notb,
    };
    kind: Kind,
    expr: Expr,
};

pub const Int = struct {
    str: []const u8,
    typ_id: usize,
};

pub const Expr = struct {
    pub const Kind = union(enum) {
        unary: *const Unary,
        infer_struc: InferStruct,
        int: Int,
        str: usize,
        vari: []const u8,
        char: u8,
        undef: Undef,
        bool: bool,
        call: Call,
        binary: *const Binary,
        field: *const Field,
        struc: StructExpr,
        elem: *const Elem,
    };
    location: Location,
    kind: Kind,
};

pub const StructExpr = struct {
    name: []const u8,
    fields: []const NewField,
    struc_id: usize,
};

pub const InferStruct = struct {
    fields: []const NewField,
    struc_id: usize,
};

pub const NewField = struct {
    name: []const u8,
    expr: Expr,
    location: Location,
};

pub const Undef = struct {
    typ_id: usize,
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,
    typ_id: usize,
};

pub const Binary = struct {
    pub const Kind = enum {
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

        pub fn prior(kind: Kind) u8 {
            switch (kind) {
                .equ, .les, .moreq => return 0,
                .orb => return 1,
                .andb => return 2,
                .add, .sub => return 3,
                .mul, .div, .rem => return 4,
            }
        }
    };

    left: Expr,
    kind: Kind,
    right: Expr,
};

pub const Struct = struct {
    name: []const u8,
    generics: []const []const u8,
    fields: []const FieldDecl,
    location: Location,
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: Typ,
    location: Location,
};

pub const Info = struct {
    typ_ids: usize,
    struc_ids: usize,
};

pub const Item = union(enum) {
    ext_fun: ExtFun,
    struc: Struct,
    fun: Fun,
};

const Ast = @This();

arena: std.heap.ArenaAllocator,
items: []const Item,
strs: []const []const u8,
location: Location,

pub fn deinit(ast: *Ast) void {
    ast.arena.deinit();
    ast.* = undefined;
}
