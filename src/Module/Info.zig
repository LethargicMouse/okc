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

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    var iter = self.items.valueIterator();
    while (iter.next()) |item| {
        item.kind.deinit(gpa);
    }
    self.items.deinit();
    self.* = undefined;
}
