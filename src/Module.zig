const std = @import("std");

const Item = @import("Item.zig");
const Location = @import("Location.zig");

items: []Item,
location: Location,

pub var arena: std.heap.ArenaAllocator = undefined;
