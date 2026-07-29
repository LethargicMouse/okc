const std = @import("std");

const Source = @This();

code: []const u8,
name: []const u8,
lines: []const []const u8,

pub fn read(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !Source {
    const code = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited) catch {
        std.log.err("failed to read `{s}`", .{path});
        return error.Handled;
    };
    var vec = std.ArrayList([]const u8).empty;
    var iter = std.mem.splitAny(u8, code, "\r\n");
    while (iter.next()) |line| {
        try vec.append(gpa, line);
    }
    const lines = try vec.toOwnedSlice(gpa);
    return .{
        .code = code,
        .name = path,
        .lines = lines,
    };
}

pub fn deinit(source: Source, gpa: std.mem.Allocator) void {
    gpa.free(source.code);
    gpa.free(source.lines);
}
