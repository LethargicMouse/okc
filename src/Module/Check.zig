const std = @import("std");

const okc = @import("okc");

io: std.Io,
gpa: std.mem.Allocator,
arena: std.mem.Allocator,
failer: *okc.Failer,
program: *okc.Program,
root: []const u8,
typ: okc.Typ.Name,
checked_mods: *std.StringHashMap(void),
check_queue: *std.ArrayList([]const u8),

pub fn deinit(self: @This()) void {
    self.modules.deinit();
    self.* = undefined;
}

pub fn itemCheckCtx(self: @This(), items: *std.StringHashMap(okc.Item.Info)) okc.Item.Check {
    return .{
        .io = self.io,
        .gpa = self.gpa,
        .arena = self.arena,
        .failer = self.failer,
        .program = self.program,
        .items = items,
        .root = self.root,
        .mod_typ = self.typ,
        .check_queue = self.check_queue,
        .checked_mods = self.checked_mods,
    };
}
