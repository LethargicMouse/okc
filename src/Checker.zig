const std = @import("std");

const Failer = @import("Failer.zig");
const Module = @import("Module.zig");
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
        try item.reg(item_check);
    }
    for (module.items) |item| {
        try item.check(item_check);
    }
    item_check.checkMain(module.location);
    self.module.checkUsage(&self.failer);
}

fn deinit(self: *@This()) void {
    self.module.deinit();
    self.vars_stack.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}
