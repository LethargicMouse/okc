const std = @import("std");

const Pos = @import("Pos.zig");

const Self = @This();
name: []const u8,
start: Pos,
end: Pos,
lines: []const []const u8,

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
        \\`{s}` at {f}:
        \\     |
    , .{ self.name, self.start });
    try line(writer, self.start.line, self.lines);
    if (self.start.line == self.end.line) {
        try underline(writer, self.start.symbol, self.end.symbol);
        return;
    }
    try underline(writer, self.start.symbol, self.lines[self.start.line - 1].len + 1);
    for (self.start.line + 1..self.end.line + 1) |i| {
        try line(writer, i, self.lines);
    }
    try underline(writer, 0, self.end.symbol);
}

fn line(writer: *std.Io.Writer, number: usize, lines: []const []const u8) std.Io.Writer.Error!void {
    try writer.print("\n{:>4} | {s}", .{ number, lines[number - 1] });
}

fn underline(writer: *std.Io.Writer, start: usize, end: usize) std.Io.Writer.Error!void {
    try writer.writeAll("\n     |");
    for (0..start) |_| {
        try writer.writeByte(' ');
    }
    for (start..end) |_| {
        try writer.writeByte('`');
    }
}

pub fn combine(a: Self, b: Self) Self {
    return .{
        .name = a.name,
        .lines = a.lines,
        .start = a.start,
        .end = b.end,
    };
}

pub const fake = Self{
    .lines = &.{},
    .name = "<unknown>",
    .start = .start,
    .end = .start,
};
