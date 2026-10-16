const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const Failer = @import("Failer.zig");
const Location = @import("Location.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/typ.zig").Typ;

name: []const u8,
kind: Kind,
location: Location,

pub fn reg(self: *@This(), ctx: Check) !void {
    const kind: Info.Kind = switch (self.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .struc => |struc| .{ .struc = try struc.reg(ctx) },
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*constt| try constt.reg(ctx),
        .use => unreachable,
    };
    if (kind == .fun) {
        try kind.fun.check(ctx);
    }
    if (ctx.items.get(self.name)) |prev| {
        ctx.failer.alreadyDeclared(self.location, self.name, prev.location);
        return;
    }
    try ctx.items.put(self.name, .{
        .location = self.location,
        .kind = kind,
    });
}

pub fn check(self: @This(), ctx: Check) error{OutOfMemory}!void {
    switch (self.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try fun.check(self.location, ctx),
        .use => unreachable,
    }
}

pub const Kind = union(enum) {
    constant: Const,
    ext_fun: Fun.Extern,
    fun: Fun,
    struc: Struct,
    typ_alias: TypAlias,
    use,
};

pub const Const = struct {
    declare: Stmt.Declare,

    pub fn reg(self: *@This(), ctx: Check) !Info.Kind {
        const hint_typ = if (self.declare.typ) |typ| typ else .any;
        const typ = try self.declare.expr.checkConst(.{ .typ = hint_typ }, ctx.checkExpr());
        if (self.declare.typ) |typ_decl| {
            _ = typ_decl.unify(typ, self.declare.expr.location, ctx.failer);
        }
        return .{ .vari = .{
            .mutable = false,
            .typ = typ,
            .can_be_mutable = true,
        } };
    }
};

pub const Struct = struct {
    generics: []const Generic,
    fields: []Field,

    pub fn reg(self: @This(), ctx: Check) !@This().Info {
        try ctx.checkGenericsRedeclare(self.generics);
        var res = @This().Info{
            .generics = self.generics,
            .fields = .init(ctx.gpa),
        };
        for (self.fields) |*field| {
            var defaulted = false;
            if (field.default) |*expr| {
                const expr_typ = try expr.checkConst(.{ .typ = field.typ }, ctx.checkExpr());
                _ = field.typ.unify(expr_typ, expr.location, ctx.failer);
                defaulted = true;
            }
            if (res.fields.get(field.name)) |prev| {
                ctx.failer.alreadyDeclared(field.location, field.name, prev.location);
                continue;
            }
            try res.fields.put(field.name, .{
                .location = field.location,
                .typ = field.typ,
                .defaulted = defaulted,
                .used = field.name[0] == '_',
            });
        }
        return res;
    }

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

    pub fn check(self: @This(), location: Location, ctx: Check) !void {
        var stmt_check: Stmt.Check = .{
            .gpa = ctx.gpa,
            .items = ctx.items,
            .ret_typ = self.header.ret_typ,
            .failer = ctx.failer,
        };
        defer stmt_check.deinit();
        for (self.header.params) |param| {
            try stmt_check.declare(param.name, param.location, .{
                .typ = param.typ,
                .mutable = false,
                .can_be_mutable = false,
            }, ctx.failer);
        }
        const control_flow = try self.body.check(&stmt_check);
        if (control_flow != .ret and !self.header.ret_typ.isVoid()) {
            ctx.failer.fail(location, "function may not return", .{});
        }
        stmt_check.freeVars(0);
    }

    pub const Extern = struct {
        header: Header,
    };

    pub const Header = struct {
        generics: []const Generic,
        params: []Param,
        ret_typ: Typ,

        pub fn check(self: *@This(), ctx: Check) !void {
            var generics_checker: Generic.Checker = try .init(ctx.gpa, self.generics);
            defer generics_checker.deinit(ctx.gpa);
            const typ_check = Typ.Check{
                .generics_checker = &generics_checker,
                .items = ctx.items.*,
                .failer = ctx.failer,
            };
            for (self.params) |*param| {
                param.typ = try param.typ.check(typ_check);
            }
            self.ret_typ = try self.ret_typ.check(typ_check);
            generics_checker.checkUsage(ctx.failer);
        }

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

    pub fn checkMain(self: @This(), location: Location) void {
        const item = self.items.getPtr("main") orelse {
            self.failer.fail(location, "`main` function not found", .{});
            return;
        };
        if (item.kind != .fun) {
            self.failer.fail(item.location, "item `main` is not a function", .{});
        }
        item.used = true;
    }

    pub fn checkExpr(self: @This()) Expr.Check {
        return .{
            .gpa = self.gpa,
            .items = self.items.*,
            .failer = self.failer,
        };
    }

    pub fn checkGenericsRedeclare(self: @This(), generics: []const Generic) !void {
        var map = std.StringHashMap(Location).init(self.gpa);
        defer map.deinit();
        for (generics) |generic| {
            if (self.items.get(generic.name)) |prev| {
                self.failer.alreadyDeclared(generic.location, generic.name, prev.location);
            }
            const entry = try map.getOrPut(generic.name);
            if (entry.found_existing) {
                self.failer.alreadyDeclared(generic.location, generic.name, entry.value_ptr.*);
            } else {
                entry.value_ptr.* = generic.location;
            }
        }
    }
};
