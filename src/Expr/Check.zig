const std = @import("std");

const okc = @import("okc");

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
program: *okc.Program,
mod_name: []const u8,
items: *std.StringHashMap(okc.Item.Info),
modules: std.StringHashMap(okc.Module.Info),
context: []const okc.Item.Fun.Param,
failer: *okc.Failer,

pub fn typCheckCtx(self: @This()) okc.Typ.Check {
    return .{
        .arena = self.arena,
        .mod_name = self.mod_name,
        .failer = self.failer,
        .gpa = self.gpa,
        .items = self.items,
    };
}

pub fn inside(self: @This(), typ: okc.Typ) ?@This() {
    var res = self;
    res.mod_name = if (typ == .name) typ.name.name else return null;
    res.items = okc.Module.getMembers(res.mod_name, self) orelse return null;
    return res;
}
