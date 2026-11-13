const std = @import("std");

const okc = @import("okc");

io: std.Io,
gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
program: *okc.Program,
failer: *okc.Failer,
checked_mods: *std.StringHashMap(void),
check_queue: *std.Deque([]const u8),
root: []const u8,

pub fn moduleCheckCtx(self: @This(), name: []const u8) okc.Module.Check {
    return .{
        .io = self.io,
        .gpa = self.gpa,
        .arena = self.arena,
        .failer = self.failer,
        .program = self.program,
        .root = self.root,
        .check_queue = self.check_queue,
        .checked_mods = self.checked_mods,
        .name = name,
    };
}

pub fn makePath(
    self: @This(),
    dirs: []const []const u8,
    name: []const u8,
    arena: *std.heap.ArenaAllocator,
) ![]const u8 {
    var len = self.root.len + name.len + 4;
    for (dirs) |dir| {
        len += dir.len + 1;
    }
    const res = try arena.allocator().alloc(u8, len);
    @memcpy(res[0..self.root.len], self.root);
    len = self.root.len + 1;
    res[len - 1] = '/';
    for (dirs) |dir| {
        @memcpy(res[len..][0..dir.len], dir);
        len += dir.len + 1;
        res[len - 1] = '/';
    }
    @memcpy(res[len..][0..name.len], name);
    len += name.len;
    @memcpy(res[len..], ".ok");
    return res;
}
