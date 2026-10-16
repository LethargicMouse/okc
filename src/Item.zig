const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const Failer = @import("Failer.zig");
const Location = @import("Location.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/typ.zig").Typ;

name: []const u8,
kind: Kind,
location: Location,

pub const Kind = union(enum) {
    constant: Stmt.Declare,
    ext_fun: Fun.Extern,
    fun: Fun,
    struc: Struct,
    typ_alias: TypAlias,
    use,
};

pub const Struct = struct {
    generics: []const Generic,
    fields: []Field,

    pub const Field = struct {
        name: []const u8,
        typ: Typ,
        default: ?Expr,
        location: Location,

        pub const Info = struct {
            location: Location,
            typ: Typ,
            defaulted: bool,
            used: bool = false,
        };
    };

    pub const Info = struct {
        generics: []const Generic,
        fields: std.StringHashMap(Field.Info),

        fn checkUsage(self: @This(), failer: *Failer) void {
            var iter = self.fields.iterator();
            while (iter.next()) |entry| {
                if (!entry.value_ptr.used) {
                    failer.unused(entry.value_ptr.location, entry.key_ptr.*);
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.fields.deinit();
            self.* = undefined;
        }
    };
};

pub const Fun = struct {
    header: Header,
    body: Stmt.Block,

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

    pub const Checker = struct {
        generics: []const Generic,
        usage: std.bit_set.Dynamic,

        pub fn init(gpa: std.mem.Allocator, generics: []const Generic) !@This() {
            return .{
                .generics = generics,
                .usage = try .initEmpty(gpa, generics.len),
            };
        }

        pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            self.usage.deinit(gpa);
            self.* = undefined;
        }

        pub fn mark(self: *@This(), name: []const u8) bool {
            for (self.generics, 0..) |generic, i| {
                if (std.mem.eql(u8, generic.name, name)) {
                    self.usage.set(i);
                    return true;
                }
            }
            return false;
        }

        pub fn checkUsage(self: *@This(), failer: *Failer) void {
            for (self.generics, 0..) |generic, i| {
                if (!self.usage.isSet(i)) {
                    failer.unused(generic.location, generic.name);
                }
            }
        }
    };
};

pub const Info = struct {
    kind: Info.Kind,
    location: Location,
    used: bool = false,

    pub fn checkUsage(self: @This(), name: []const u8, failer: *Failer) void {
        if (self.used) {
            switch (self.kind) {
                .fun, .typ => {},
                .vari => |vari| vari.checkUsage(self.location, failer),
                .struc => |struc| struc.checkUsage(failer),
            }
        } else {
            failer.unused(self.location, name);
        }
    }

    pub const Kind = union(enum) {
        fun: *Fun.Header,
        struc: Struct.Info,
        typ: Typ,
        vari: Stmt.Declare.Info,

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                .struc => |*struc| struc.deinit(),
                .fun, .vari, .typ => {},
            }
            self.* = undefined;
        }
    };
};

pub const Check = struct {
    gpa: std.mem.Allocator,
    items: *std.StringHashMap(Info),
    failer: *Failer,
};
