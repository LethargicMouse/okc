const std = @import("std");

const okc = @import("okc");

name: []const u8,
items: std.StringHashMap(okc.Item.Kind),

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
