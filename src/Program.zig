const std = @import("std");

const okc = @import("okc");

ast_modules: std.StringHashMap(okc.Module),
modules: std.StringHashMap(okc.Module.Info),

pub fn init(gpa: std.mem.Allocator) @This() {
    return .{
        .ast_modules = .init(gpa),
        .modules = .init(gpa),
    };
}

pub fn deinit(self: *@This()) void {
    var iter = self.modules.valueIterator();
    while (iter.next()) |module| {
        module.deinit();
    }
    self.modules.deinit();
    self.ast_modules.deinit();
    self.* = undefined;
}
