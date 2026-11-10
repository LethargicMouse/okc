const std = @import("std");

const okc = @import("okc");

io: std.Io,
gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
items: *std.StringHashMap(okc.Item.Info),
program: *okc.Program,
failer: *okc.Failer,
mod_typ: okc.Typ.Name,
root: []const u8,
checked_mods: *std.StringHashMap(void),
check_queue: *std.Deque([]const u8),

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

pub fn typCheckCtx(self: @This()) okc.Typ.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items.*,
        .failer = self.failer,
        .mod_typ = self.mod_typ,
    };
}

pub fn stmtCheckCtx(
    self: @This(),
    header: okc.Item.Fun.Header,
) okc.Stmt.Check {
    return .{
        .gpa = self.gpa,
        .arena = self.arena,
        .items = self.items,
        .failer = self.failer,
        .modules = self.program.modules,
        .mod_typ = self.mod_typ,
        .header = header,
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
        .context = &.{},
    };
}
