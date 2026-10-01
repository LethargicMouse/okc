const std = @import("std");

const Self = @This();
code: []const u8,
name: []const u8,
lines: []const []const u8,

const Error = error{ OutOfMemory, Handled };

pub fn read(io: std.Io, gpa: std.mem.Allocator, path: []const u8) Error!Self {
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

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    gpa.free(self.code);
    gpa.free(self.lines);
    self.* = undefined;
}
