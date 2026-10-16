const std = @import("std");

const Failer = @import("Failer.zig");
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
    const item_check: Item.Check = .{
        .gpa = self.gpa,
        .failer = &self.failer,
        .items = &self.module.items,
    };
    for (module.items) |*item| {
        try self.regItem(item, item_check);
    }
    for (module.items) |item| {
        try checkItem(item, item_check);
    }
    item_check.checkMain(module.location);
    self.checkItemsUsage();
}

fn checkItemsUsage(self: *@This()) void {
    var iter = self.module.items.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.checkUsage(entry.key_ptr.*, &self.failer);
    }
}

fn regItem(self: *@This(), item: *Item, ctx: Item.Check) !void {
    const kind: Item.Info.Kind = switch (item.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .struc => |struc| .{ .struc = try struc.reg(ctx) },
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*declare| try self.regConst(declare),
        .use => unreachable,
    };
    if (kind == .fun) {
        try kind.fun.check(ctx);
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
    const typ = try declare.expr.checkConst(.{ .typ = hint_typ }, .{
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

fn checkItem(item: Item, ctx: Item.Check) error{OutOfMemory}!void {
    switch (item.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try fun.check(item.location, ctx),
        .use => unreachable,
    }
}

fn deinit(self: *@This()) void {
    self.module.deinit();
    self.vars_stack.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}
