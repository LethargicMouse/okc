const std = @import("std");

const okc = @import("okc");

items: std.StringHashMap(okc.Item.Info),

pub fn checkMain(self: @This(), location: okc.Location, ctx: okc.Module.Check) void {
    const item = self.items.getPtr("main") orelse {
        ctx.failer.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        ctx.failer.fail(item.location, "item `main` is not a function", .{});
    }
    item.used = true;
}

pub fn load(dirs: []const []const u8, name: []const u8, location: okc.Location, ctx: Load) !@This() {
    if (ctx.program.modules.get(name)) |res| {
        return res;
    }
    const path = try ctx.makePath(dirs, name, ctx.arena);
    const module: okc.Module = try .read(ctx.io, ctx.gpa, path, ctx.arena, location);
    try ctx.program.ast_modules.put(name, module);
    if (!ctx.checked_mods.contains(name)) {
        try ctx.check_queue.pushBack(ctx.gpa, name);
        try ctx.checked_mods.put(name, {});
    }
    const res = try module.makeInfo(ctx.moduleCheckCtx(.{ .name = name }));
    try ctx.program.modules.put(name, res);
    return res;
}

pub fn checkUsage(self: @This(), failer: *okc.Failer) void {
    var iter = self.items.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.checkUsage(entry.key_ptr.*, failer);
    }
}

pub fn init(gpa: std.mem.Allocator) @This() {
    return .{
        .items = .init(gpa),
    };
}

pub fn deinit(self: *@This()) void {
    var iter = self.items.valueIterator();
    while (iter.next()) |item| {
        item.kind.deinit();
    }
    self.items.deinit();
    self.* = undefined;
}

pub const Load = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    program: *okc.Program,
    failer: *okc.Failer,
    checked_mods: *std.StringHashMap(void),
    check_queue: *std.Deque([]const u8),
    root: []const u8,

    pub fn moduleCheckCtx(self: @This(), typ: okc.Typ.Name) okc.Module.Check {
        return .{
            .io = self.io,
            .gpa = self.gpa,
            .arena = self.arena,
            .failer = self.failer,
            .program = self.program,
            .root = self.root,
            .check_queue = self.check_queue,
            .checked_mods = self.checked_mods,
            .typ = typ,
        };
    }

    fn makePath(self: @This(), dirs: []const []const u8, name: []const u8, arena: std.mem.Allocator) ![]const u8 {
        var len = self.root.len + name.len + 4;
        for (dirs) |dir| {
            len += dir.len + 1;
        }
        const res = try arena.alloc(u8, len);
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
};
