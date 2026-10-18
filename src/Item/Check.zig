const std = @import("std");

const okc = @import("okc");

io: std.Io,
gpa: std.mem.Allocator,
arena: std.mem.Allocator,
items: *std.StringHashMap(okc.Item.Info),
program: *okc.Program,
failer: *okc.Failer,
mod_typ: okc.Typ.Name,
root: []const u8,
checked_mods: *std.StringHashMap(void),
check_queue: *std.ArrayList([]const u8),

pub fn loadCtx(self: @This()) okc.Module.Info.Load {
    return .{
        .io = self.io,
        .gpa = self.gpa,
        .arena = self.arena,
        .program = self.program,
        .failer = self.failer,
        .root = self.root,
        .checked_mods = self.checked_mods,
        .check_queue = self.check_queue,
    };
}

pub fn checkTyp(self: @This(), generics_checker: *okc.Item.Generic.Checker) okc.Typ.Check {
    return .{
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
        .generics_checker = generics_checker,
        .mod_typ = self.mod_typ,
    };
}

pub fn checkStmt(self: @This(), ret_typ: okc.Typ) okc.Stmt.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items,
        .failer = self.failer,
        .modules = self.program.modules,
        .mod_typ = self.mod_typ,
        .ret_typ = ret_typ,
    };
}

pub fn checkExprCtx(self: @This()) okc.Expr.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
        .modules = self.program.modules,
        .mod_typ = self.mod_typ,
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
