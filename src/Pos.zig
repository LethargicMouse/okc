const std = @import("std");

const Pos = @This();

line: u32,
symbol: u32,

pub fn makePoses(gpa: std.mem.Allocator, code: []const u8) ![]const Pos {
    var vec = try std.ArrayList(Pos).initCapacity(gpa, code.len + 2);
    var current = Pos{ .line = 1, .symbol = 1 };
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

pub fn format(pos: Pos, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{}:{}", .{ pos.line, pos.symbol });
}
