const std = @import("std");

const Item = @import("Item.zig");
const Location = @import("Location.zig");

items: []Item,
location: Location,

pub const Info = struct {
    items: std.StringHashMap(Item.Info),

    pub fn init(gpa: std.mem.Allocator) @This() {
        return .{
            .items = .init(gpa),
        };
    }

    pub fn deinit(self: *@This()) void {
        var iter = self.items.valueIterator();
        while (iter.next()) |item| {
            item.deinit();
        }
        self.items.deinit();
        self.* = undefined;
    }
};

pub var arena: std.mem.Allocator = undefined;
