const std = @import("std");

const okc = @import("okc");

gpa: std.mem.Allocator,
arena: std.mem.Allocator,
items: *std.StringHashMap(okc.Item.Info),
vars_stack: std.ArrayList([]const u8) = .empty,
loops_nested: u16 = 0,
ret_typ: okc.Typ,
failer: *okc.Failer,
modules: std.StringHashMap(okc.Module.Info),
mod_typ: okc.Typ.Name,

pub fn deinit(self: *@This()) void {
    self.vars_stack.deinit(self.gpa);
    self.* = undefined;
}

pub fn declare(
    self: *@This(),
    name: []const u8,
    location: okc.Location,
    vari: okc.Stmt.Declare.Info,
    failer: *okc.Failer,
) !void {
    if (self.items.get(name)) |prev| {
        failer.alreadyDeclared(location, name, prev.location);
        return;
    }
    try self.vars_stack.append(self.gpa, name);
    try self.items.put(name, .{
        .location = location,
        .kind = .{ .vari = vari },
    });
}

pub fn exprCheck(self: @This()) okc.Expr.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
        .modules = self.modules,
        .mod_typ = self.mod_typ,
    };
}

pub fn freeVars(self: *@This(), rbp: usize) void {
    for (self.vars_stack.items[rbp..]) |name| {
        self.freeVar(name);
    }
    self.vars_stack.shrinkRetainingCapacity(rbp);
}

pub fn freeVar(self: @This(), name: []const u8) void {
    const item = self.items.fetchRemove(name).?.value;
    item.checkUsage(name, self.failer);
}
