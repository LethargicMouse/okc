const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const fail = @import("fail.zig");
const Location = @import("Location.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/typ.zig").Typ;

name: []const u8,
kind: Kind,
location: Location,

pub const Kind = union(enum) {
    constant: Declare,
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

        pub fn deinit(self: *@This()) void {
            self.fields.deinit();
            self.* = undefined;
        }
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

        pub fn checkUsage(self: *@This()) void {
            for (self.generics, 0..) |generic, i| {
                if (!self.usage.isSet(i)) {
                    fail.unused(generic.location, generic.name);
                }
            }
        }
    };
};

pub const Info = struct {
    pub const Kind = union(enum) {
        fun: *Fun.Header,
        struc: Struct.Info,
        typ: Typ,
        vari: Declare.Info,
    };
    kind: Info.Kind,
    location: Location,
    used: bool = false,

    pub fn deinit(self: *@This()) void {
        switch (self.kind) {
            .struc => |*struc| struc.deinit(),
            .fun, .vari, .typ => {},
        }
    }
};

pub const Declare = struct {
    typ: ?Typ,
    expr: Expr,
    mutable: bool,

    pub const Named = struct {
        name: []const u8,
        bare: Declare,

        pub fn check(self: *@This(), location: Location, ctx: Stmt.Check) !Stmt.ControlFlow {
            const typ_decl = if (self.bare.typ) |typ| typ else .any;
            const info = try self.bare.expr.check(.{ .typ = typ_decl }, ctx.exprCheck());
            const typ = typ_decl.unify(info.typ, self.bare.expr.location);
            const vari: Declare.Info = .{
                .typ = typ,
                .mutable = self.bare.mutable,
                .can_be_mutable = true,
            };
            try vari.declare(self.name, location, ctx);
            return .cont;
        }
    };

    pub const Info = struct {
        typ: Typ,
        can_be_mutable: bool,
        mutable: bool,
        mutated: bool = false,

        pub fn declare(
            self: @This(),
            name: []const u8,
            location: Location,
            ctx: Stmt.Check,
        ) !void {
            if (ctx.items.get(name)) |prev| {
                fail.alreadyDeclared(location, name, prev.location);
                return;
            }
            try ctx.vars_stack.append(ctx.gpa, name);
            try ctx.items.put(name, .{
                .location = location,
                .kind = .{ .vari = self },
            });
        }
    };
};
