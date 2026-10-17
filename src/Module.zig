const std = @import("std");

const okc = @import("okc");

pub const GenInfo = @import("Module/GenInfo.zig");
pub const Info = @import("Module/Info.zig");

items: []okc.Item,
location: okc.Location,

pub fn check(self: @This(), gpa: std.mem.Allocator, arena: std.mem.Allocator, failer: *okc.Failer) !void {
    var info: Info = .init(gpa);
    defer info.deinit();
    const item_check: okc.Item.Check = .{
        .gpa = gpa,
        .arena = arena,
        .failer = failer,
        .items = &info.items,
    };
    for (self.items) |*item| {
        try item.reg(item_check);
    }
    for (self.items) |item| {
        try item.check(item_check);
    }
    item_check.checkMain(self.location);
    info.checkUsage(failer);
}
