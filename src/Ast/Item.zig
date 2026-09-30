const Location = @import("../Location.zig");
const Expr = @import("Expr/mod.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ.zig").Typ;

const Item = @This();
kind: Kind,
location: Location,

pub const Kind = union(enum) {
    ext_fun: Fun.Extern,
    struc: Struct,
    fun: Fun,
    constant: Stmt.Declare,
    typ_alias: TypAlias,
};

pub fn getName(item: Item) []const u8 {
    return switch (item.kind) {
        .ext_fun => |ext_fun| ext_fun.header.name,
        .struc => |struc| struc.name,
        .fun => |fun| fun.header.name,
        .constant => |declare| declare.name,
        .typ_alias => |typ| typ.name,
    };
}

pub fn getHeader(item: Item) ?Fun.Header {
    return switch (item.kind) {
        .ext_fun => |ext_fun| ext_fun.header,
        .fun => |fun| fun.header,
        .constant, .struc, .typ_alias => null,
    };
}

pub const Struct = struct {
    name: []const u8,
    generics: []const Generic,
    fields: []Field,

    pub const Field = struct {
        name: []const u8,
        typ: Typ,
        default: ?Expr,
        location: Location,
    };
};

pub const Fun = struct {
    header: Header,
    body: []Stmt,

    pub const Extern = struct {
        header: Header,
    };

    pub const Header = struct {
        name: []const u8,
        generics: []const Generic,
        params: []const Param,
        ret_typ: Typ,

        pub const Param = struct {
            name: []const u8,
            typ: Typ,
            location: Location,
        };
    };
};

pub const TypAlias = struct {
    name: []const u8,
    typ: Typ,
};

pub const Generic = struct {
    name: []const u8,
    location: Location,
};
