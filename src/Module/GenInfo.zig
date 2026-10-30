const std = @import("std");

const okc = @import("okc");

name: []const u8,
items: std.StringHashMap(okc.Item.Kind),

pub fn get(name: []const u8, ctx: *okc.Codegen) !*@This() {
    if (ctx.modules.get(name)) |mod| {
        return mod;
    }
    std.log.debug("new gen mod `{s}`", .{name});
    const new = try ctx.ast_modules.get(name).?.makeGenInfo(ctx.gpa, name);
    try ctx.modules.put(name, new);
    return new;
}

pub fn init(gpa: std.mem.Allocator, name: []const u8) @This() {
    return .{
        .name = name,
        .items = .init(gpa),
    };
}

pub fn deinit(self: *@This()) void {
    self.items.deinit();
    self.* = undefined;
}
