const Location = @import("../Location.zig");
const Expr = @import("Expr/mod.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("../typ/mod.zig").Typ;

const Self = @This();
name: []const u8,
kind: Kind,
location: Location,

pub const Kind = union(enum) {
    ext_fun: Fun.Extern,
    struc: Struct,
    fun: Fun,
    constant: Stmt.Declare,
    typ_alias: TypAlias,
    use: []const u8,
};

pub const Struct = struct {
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
        generics: []const Generic,
        params: []Param,
        ret_typ: Typ,

        pub const Param = struct {
            name: []const u8,
            typ: Typ,
            location: Location,
        };
    };
};

pub const TypAlias = struct {
    typ: Typ,
};

pub const Generic = struct {
    name: []const u8,
    location: Location,
};
