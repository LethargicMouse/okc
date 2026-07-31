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
    // for now we only deal with one-liners
    std.debug.assert(location.start.line == location.end.line);
    try line(writer, location.start.line, location.lines);
    try underline(writer, location.start.symbol, location.end.symbol);
}

fn line(writer: *std.Io.Writer, number: u32, lines: []const []const u8) std.Io.Writer.Error!void {
    try writer.print("\n{:>4} | {s}", .{ number, lines[number - 1] });
}

fn underline(writer: *std.Io.Writer, start: u32, end: u32) std.Io.Writer.Error!void {
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
