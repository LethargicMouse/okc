const std = @import("std");

items: []const []const u8,

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    if (self.items.len != 0) {
        try writer.writeAll(self.items[0]);
        for (self.items[1..]) |item| {
            try writer.print(" {s}", .{item});
        }
    }
}
