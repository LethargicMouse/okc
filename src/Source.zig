const std = @import("std");

const okc = @import("okc");

code: []const u8,
name: []const u8,
lines: []const []const u8,

const Error = error{ OutOfMemory, Handled };

pub fn read(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    path: []const u8,
    maybe_location: ?okc.Location,
) Error!@This() {
    const code = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch {
        if (maybe_location) |location| {
            std.log.err("{f}\n     failed to read `{s}`", .{ location, path });
        } else {
            std.log.err("failed to read `{s}`", .{path});
        }
        return error.Handled;
    };
    var vec = std.ArrayList([]const u8).empty;
    defer vec.deinit(gpa);
    var iter = std.mem.splitAny(u8, code, "\r\n");
    while (iter.next()) |line| {
        try vec.append(gpa, line);
    }
    const lines = try arena.dupe([]const u8, vec.items);
    return .{
        .code = code,
        .name = path,
        .lines = lines,
    };
}
