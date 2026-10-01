const std = @import("std");

const Self = @This();
line: u32,
symbol: u32,

pub fn makePoses(gpa: std.mem.Allocator, code: []const u8) error{OutOfMemory}![]const Self {
    var vec = try std.ArrayList(Self).initCapacity(gpa, code.len + 2);
    var current = start;
    for (code) |c| {
        try vec.append(gpa, current);
        if (c == '\n') {
            current.line += 1;
            current.symbol = 1;
        } else {
            current.symbol += 1;
        }
    }
    // additional poses for eof lexeme
    for (0..2) |_| {
        try vec.append(gpa, current);
        current.symbol += 1;
    }
    return vec.toOwnedSlice(gpa);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{}:{}", .{ self.line, self.symbol });
}

pub const start = Self{ .line = 1, .symbol = 1 };
