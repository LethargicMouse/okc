const std = @import("std");

const okc = @import("okc");

gpa: std.mem.Allocator,
tokens: []const okc.Lexer.Token,
arena: *std.heap.ArenaAllocator,
err_msgs: std.ArrayList([]const u8) = .empty,
tmp_name: []const u8 = "<unknown>",
tmp_location: okc.Location = .fake,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    tokens: []const okc.Lexer.Token,
) @This() {
    return .{
        .gpa = gpa,
        .arena = arena,
        .tokens = tokens,
    };
}

pub fn sep(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    if (try self.maybe(parse, args)) |first| {
        try vec.append(self.gpa, first);
        while (true) {
            try self.maybe(expect, .{ .comma, .quiet }) orelse break;
            if (try self.maybe(parse, args)) |item| {
                try vec.append(self.gpa, item);
            } else break;
        }
    }
    const slice = try self.arena.allocator().dupe(ParseRes(parse, args), vec.items);
    return slice;
}

pub fn either(self: *@This(), comptime parses: anytype) !ParseRes(parses[0], .{}) {
    inline for (parses) |parse| {
        if (try self.maybe(parse, .{})) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

pub fn many(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    return self.manyTo(&vec, parse, args);
}

pub fn manyTo(self: *@This(), vec: anytype, parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    while (try self.maybe(parse, args)) |item| {
        try vec.append(self.gpa, item);
    }
    const slice = try self.arena.allocator().dupe(ParseRes(parse, args), vec.items);
    return slice;
}

fn ParseRes(fun: anytype, args: anytype) type {
    return @typeInfo(@TypeOf(@call(.auto, fun, .{@as(*@This(), undefined)} ++ args)))
        .error_union.payload;
}

pub fn maybe(self: *@This(), parse: anytype, args: anytype) !?ParseRes(parse, args) {
    const cursor_before = self.cursor;
    const res = @call(.auto, parse, .{self} ++ args) catch |err| switch (err) {
        error.ParseFailed => {
            self.cursor = cursor_before;
            return null;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    return res;
}

pub fn getLocation(self: @This()) okc.Location {
    return self.tokens[self.cursor].location;
}

pub fn parseName(self: *@This(), mode: Mode) ![]const u8 {
    return try self.maybe(parseLexeme, .{.name}) orelse {
        if (mode == .loud) {
            try self.fail("<name>");
        }
        return error.ParseFailed;
    };
}

pub fn parseInt(self: *@This()) !u64 {
    return self.parseLexeme(.int);
}

fn parseLexeme(
    self: *@This(),
    comptime tag: @typeInfo(okc.Lexeme).@"union".tag_type.?,
) Error!@typeInfo(okc.Lexeme).@"union".field_types[@backingInt(tag)] {
    const next = self.tokens[self.cursor].lexeme;
    if (next == tag) {
        self.cursor += 1;
        return @field(next, @tagName(tag));
    }
    return error.ParseFailed;
}

pub fn deinit(self: *@This()) void {
    self.gpa.free(self.tokens);
    self.err_msgs.deinit(self.gpa);
    self.* = undefined;
}

pub fn expect(self: *@This(), lexeme: @typeInfo(okc.Lexeme).@"union".tag_type.?, mode: Mode) !void {
    if (self.tokens[self.cursor].lexeme == lexeme) {
        self.cursor += 1;
    } else {
        if (mode == .loud) {
            try self.fail(okc.Lexeme.describe(lexeme));
        }
        return error.ParseFailed;
    }
}

pub fn fail(self: *@This(), msg: []const u8) !void {
    switch (std.math.order(self.cursor, self.err_cursor)) {
        .lt => {},
        .eq => {
            try self.err_msgs.append(self.gpa, msg);
        },
        .gt => {
            self.err_msgs.clearRetainingCapacity();
            try self.err_msgs.append(self.gpa, msg);
            self.err_cursor = self.cursor;
        },
    }
}

const Error = error{ ParseFailed, OutOfMemory };

pub const ErrMsgsPrinter = struct {
    msgs: []const []const u8,
    found: []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.msgs.len == 1) {
            try writer.print("     expected  {s}\n        found  {s}", .{ self.msgs[0], self.found });
            return;
        }
        try writer.writeAll("     expected:");
        for (self.msgs) |msg| {
            try writer.print("\n       - {s}", .{msg});
        }
        try writer.print("\n     found  {s}", .{self.found});
    }
};

pub const Mode = enum {
    loud,
    quiet,
};
