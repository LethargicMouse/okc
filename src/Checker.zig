const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const Failer = @import("Failer.zig");
const Location = @import("Location.zig");
const Module = @import("Module.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/typ.zig").Typ;
const Item = @import("Item.zig");

gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
vars_stack: std.ArrayList([]const u8) = .empty,
module: Module.Info,
ret_typ: Typ = .any,
loops_nested: u16 = 0,
failer: Failer = .init(),

pub fn init(
    gpa: std.mem.Allocator,
) error{OutOfMemory}!@This() {
    return .{
        .gpa = gpa,
        .arena = .init(gpa),
        .module = .init(gpa),
    };
}

pub fn run(self: *@This(), module: Module) error{ OutOfMemory, Handled }!void {
    defer self.deinit();
    try self.checkModule(module);
    try self.failer.ensureNoErrors();
    return;
}

fn checkModule(self: *@This(), module: Module) !void {
    for (module.items) |*item| {
        try self.regItem(item);
    }
    for (module.items) |item| {
        try checkItem(item, .{
            .gpa = self.gpa,
            .items = &self.module.items,
            .failer = &self.failer,
        });
    }
    self.checkMain(module.location);
    self.checkItemsUsage();
}

fn checkItemsUsage(self: *@This()) void {
    var iter = self.module.items.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.checkUsage(entry.key_ptr.*, &self.failer);
    }
}

fn regItem(self: *@This(), item: *Item) !void {
    const kind: Item.Info.Kind = switch (item.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .struc => |struc| try self.regStruct(struc),
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*declare| try self.regConst(declare),
        .use => unreachable,
    };
    if (kind == .fun) {
        try self.checkHeader(kind.fun);
    }
    if (self.module.items.get(item.name)) |prev| {
        self.failer.alreadyDeclared(item.location, item.name, prev.location);
        return;
    }
    try self.module.items.put(item.name, .{
        .location = item.location,
        .kind = kind,
    });
}

fn regConst(self: *@This(), declare: *Stmt.Declare) !Item.Info.Kind {
    const hint_typ = if (declare.typ) |typ| typ else .any;
    const typ = try self.checkConstExpr(&declare.expr, .{ .typ = hint_typ }, .{
        .gpa = self.gpa,
        .items = self.module.items,
        .failer = &self.failer,
    });
    if (declare.typ) |typ_decl| {
        _ = typ_decl.unify(typ, declare.expr.location, &self.failer);
    }
    return .{ .vari = .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    } };
}

fn checkConstExpr(self: *@This(), expr: *Expr, hint: Expr.Hint, ctx: Expr.Check) !Typ {
    const info = try expr.check(hint, ctx);
    self.checkExprComptime(expr.*);
    return info.typ;
}

fn checkExprComptime(self: *@This(), expr: Expr) void {
    switch (expr.kind) {
        .str, .bool, .char, .int, .sizeof, .vari, .undef => {},
        .call, .method => self.failer.fail(expr.location, "cannot evaluate at compile time", .{}),
        .field => |field| self.checkExprComptime(field.expr),
        .unary => |unary| self.checkExprComptime(unary.expr),
        .elem => |elem| self.checkElemComptime(elem.*),
        .binary => |binary| self.checkBinaryComptime(binary.*),
        .subslice => |subslice| self.checkSubsliceComptime(subslice.*),
        .array => |array| self.checkArrayComptime(array),
        .named_struc => |named| self.checkStructExprComptime(named.struc),
        .struc => |struc| self.checkStructExprComptime(struc),
    }
}

fn checkElemComptime(self: *@This(), elem: Expr.Elem) void {
    self.checkExprComptime(elem.expr);
    self.checkExprComptime(elem.index);
}

fn checkBinaryComptime(self: *@This(), binary: Expr.Binary) void {
    self.checkExprComptime(binary.left);
    self.checkExprComptime(binary.right);
}

fn checkSubsliceComptime(self: *@This(), subslice: Expr.Subslice) void {
    self.checkExprComptime(subslice.expr);
    self.checkExprComptime(subslice.start);
    self.checkExprComptime(subslice.end);
}

fn checkStructExprComptime(self: *@This(), struc: Expr.Struct) void {
    for (struc.fields) |field| {
        self.checkExprComptime(field.expr);
    }
}

fn checkArrayComptime(self: *@This(), array: Expr.Array) void {
    for (array.exprs) |elem| {
        self.checkExprComptime(elem);
    }
}

fn checkItem(item: Item, ctx: Item.Check) error{OutOfMemory}!void {
    switch (item.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try checkFun(fun, item.location, ctx),
        .use => unreachable,
    }
}

fn checkHeader(self: *@This(), header: *Item.Fun.Header) !void {
    var generics_checker: Item.Generic.Checker = try .init(self.gpa, header.generics);
    defer generics_checker.deinit(self.gpa);
    const typ_check = Typ.Check{
        .generics_checker = &generics_checker,
        .items = self.module.items,
        .failer = &self.failer,
    };
    for (header.params) |*param| {
        param.typ = try param.typ.check(typ_check);
    }
    header.ret_typ = try header.ret_typ.check(typ_check);
    generics_checker.checkUsage(&self.failer);
}

fn checkMain(self: *@This(), location: Location) void {
    const item = self.module.items.getPtr("main") orelse {
        self.failer.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        self.failer.fail(item.location, "item `main` is not a function", .{});
    }
    item.used = true;
}

fn regStruct(self: *@This(), struc: Item.Struct) !Item.Info.Kind {
    try self.checkGenericsRedeclare(struc.generics);
    var res = Item.Struct.Info{
        .generics = struc.generics,
        .fields = .init(self.gpa),
    };
    for (struc.fields) |*field| {
        var defaulted = false;
        if (field.default) |*expr| {
            const expr_typ = try self.checkConstExpr(expr, .{ .typ = field.typ }, .{
                .gpa = self.gpa,
                .items = self.module.items,
                .failer = &self.failer,
            });
            _ = field.typ.unify(expr_typ, expr.location, &self.failer);
            defaulted = true;
        }
        if (res.fields.get(field.name)) |prev| {
            self.failer.alreadyDeclared(field.location, field.name, prev.location);
            continue;
        }
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = field.typ,
            .defaulted = defaulted,
            .used = field.name[0] == '_',
        });
    }
    return .{ .struc = res };
}

fn checkGenericsRedeclare(self: *@This(), generics: []const Item.Generic) !void {
    var map = std.StringHashMap(Location).init(self.gpa);
    defer map.deinit();
    for (generics) |generic| {
        if (self.module.items.get(generic.name)) |prev| {
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

fn checkFun(fun: Item.Fun, location: Location, ctx: Item.Check) !void {
    var stmt_check: Stmt.Check = .{
        .gpa = ctx.gpa,
        .items = ctx.items,
        .ret_typ = fun.header.ret_typ,
        .failer = ctx.failer,
    };
    defer stmt_check.deinit();
    for (fun.header.params) |param| {
        try stmt_check.declare(param.name, param.location, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        }, ctx.failer);
    }
    const control_flow = try fun.body.check(&stmt_check);
    if (control_flow != .ret and !fun.header.ret_typ.isVoid()) {
        ctx.failer.fail(location, "function may not return", .{});
    }
    stmt_check.freeVars(0);
}

fn deinit(self: *@This()) void {
    self.module.deinit();
    self.vars_stack.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}
