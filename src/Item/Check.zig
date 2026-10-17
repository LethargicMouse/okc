const std = @import("std");

const okc = @import("okc");

gpa: std.mem.Allocator,
arena: std.mem.Allocator,
items: *std.StringHashMap(okc.Item.Info),
failer: *okc.Failer,

pub fn checkTyp(self: @This(), generics_checker: *okc.Item.Generic.Checker) okc.Typ.Check {
    return .{
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
        .generics_checker = generics_checker,
    };
}

pub fn checkStmt(self: @This(), ret_typ: okc.Typ) okc.Stmt.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items,
        .failer = self.failer,
        .ret_typ = ret_typ,
    };
}

pub fn checkMain(self: @This(), location: okc.Location) void {
    const item = self.items.getPtr("main") orelse {
        self.failer.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        self.failer.fail(item.location, "item `main` is not a function", .{});
    }
    item.used = true;
}

pub fn checkExprCtx(self: @This()) okc.Expr.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
    };
}

pub fn checkGenericsRedeclare(self: @This(), generics: []const okc.Item.Generic) !void {
    var map = std.StringHashMap(okc.Location).init(self.gpa);
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
