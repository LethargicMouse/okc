const std = @import("std");

const okc = @import("okc");

items: std.StringHashMap(okc.Item.Info),

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
