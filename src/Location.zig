const std = @import("std");

const Pos = @import("Pos.zig");

const Location = @This();

name: []const u8,
start: Pos,
end: Pos,
lines: []const []const u8,

pub fn format(location: Location, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
        \\`{s}` at {f}:
        \\     |
    , .{ location.name, location.start });
    try line(writer, location.start.line, location.lines);
    if (location.start.line == location.end.line) {
        try underline(writer, location.start.symbol, location.end.symbol);
        return;
    }
    try underline(writer, location.start.symbol, location.lines[location.start.line - 1].len);
    for (location.start.line + 1..location.end.line + 1) |i| {
        try line(writer, i, location.lines);
    }
    try underline(writer, 0, location.end.symbol);
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

pub fn combine(a: Location, b: Location) Location {
    return .{
        .name = a.name,
        .lines = a.lines,
        .start = a.start,
        .end = b.end,
    };
}
