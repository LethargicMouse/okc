const std = @import("std");

const Location = @import("Location.zig");
const Pos = @import("Pos.zig");
const Source = @import("Source.zig");

pub const Token = struct { lexeme: Lexeme, location: Location };

pub const Lexeme = union(enum) {
    name: []const u8,
    int: []const u8,
    amp,
    star,
    colon,
    ext,
    fun,
    parl,
    parr,
    curl,
    curr,
    ret,
    semi,
    eof,
    unknown,

    pub fn eq(a: Lexeme, b: Lexeme) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) {
            return false;
        }
        return switch (a) {
            .name => |an| switch (b) {
                .name => |bn| std.mem.eql(u8, an, bn),
                else => false,
            },
            .int => |ai| switch (b) {
                .int => |bi| std.mem.eql(u8, ai, bi),
                else => false,
            },
            else => true,
        };
    }

    pub fn describe(lexeme: Lexeme) []const u8 {
        return switch (lexeme) {
            .amp => "`&`",
            .star => "`*`",
            .colon => "`:`",
            .ext => "`extern`",
            .fun => "`fn`",
            .parl => "`(`",
            .parr => "`)`",
            .curl => "`{`",
            .semi => "`;`",
            .curr => "`}`",
            .eof => "<eof>",
            else => {
                std.debug.print("bad describe: {any}", .{lexeme});
                unreachable;
            },
        };
    }
};

const LexPair = struct { prefix: []const u8, lexeme: Lexeme };

const Lexer = @This();

source: Source,
poses: []const Pos,
cursor: usize = 0,

pub fn init(gpa: std.mem.Allocator, source: Source) !Lexer {
    const poses = try Pos.makePoses(gpa, source.code);
    return .{ .source = source, .poses = poses };
}

pub fn lex(lexer: *Lexer, gpa: std.mem.Allocator) ![]const Token {
    defer lexer.deinit(gpa);
    var vec = std.ArrayList(Token).empty;
    try lexer.populate(gpa, &vec);
    return vec.toOwnedSlice(gpa);
}

fn populate(lexer: *Lexer, gpa: std.mem.Allocator, res: *std.ArrayList(Token)) !void {
    while (true) {
        const before_skip = lexer.cursor;
        lexer.skipSpaces();
        if (lexer.cursor == lexer.source.code.len) {
            // so that eof is right after last lexeme
            lexer.cursor = before_skip;
            try res.append(gpa, lexer.makeToken(.eof, 1));
            break;
        }
        if (lexer.lexNext()) |token| {
            try res.append(gpa, token);
            continue;
        }
        try res.append(gpa, lexer.makeToken(.unknown, 1));
        break;
    }
}

fn skipSpaces(lexer: *Lexer) void {
    const spaces = lexer.takeWhile(std.ascii.isWhitespace);
    lexer.cursor += spaces.len;
}

fn lexNext(lexer: *Lexer) ?Token {
    return lexer.lexByList() orelse lexer.lexName() orelse lexer.lexInt();
}

fn lexInt(lexer: *Lexer) ?Token {
    const res = lexer.takeWhile(std.ascii.isDigit);
    if (res.len == 0) {
        return null;
    }
    return lexer.makeToken(.{ .int = res }, res.len);
}

fn lexByList(lexer: *Lexer) ?Token {
    for (lex_list) |pair| {
        if (std.mem.startsWith(u8, lexer.rest(), pair.prefix)) {
            return lexer.makeToken(pair.lexeme, pair.prefix.len);
        }
    }
    return null;
}

const lex_list = [_]LexPair{
    .{ .prefix = "&", .lexeme = .amp },
    .{ .prefix = "*", .lexeme = .star },
    .{ .prefix = ":", .lexeme = .colon },
    .{ .prefix = "extern", .lexeme = .ext },
    .{ .prefix = ";", .lexeme = .semi },
    .{ .prefix = "fn", .lexeme = .fun },
    .{ .prefix = "(", .lexeme = .parl },
    .{ .prefix = ")", .lexeme = .parr },
    .{ .prefix = "{", .lexeme = .curl },
    .{ .prefix = "}", .lexeme = .curr },
    .{ .prefix = "return", .lexeme = .ret },
};

fn rest(lexer: Lexer) []const u8 {
    return lexer.source.code[lexer.cursor..];
}

fn lexName(lexer: *Lexer) ?Token {
    const res = lexer.takeWhile(isNameChar);
    if (res.len != 0 and isNameFirstChar(res[0])) {
        return lexer.makeToken(.{ .name = res }, res.len);
    }
    return null;
}

fn takeWhile(lexer: Lexer, predicate: fn (u8) bool) []const u8 {
    var i = lexer.cursor;
    while (i < lexer.source.code.len and predicate(lexer.source.code[i])) {
        i += 1;
    }
    return lexer.source.code[lexer.cursor..i];
}

fn isNameFirstChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isNameChar(c: u8) bool {
    return isNameFirstChar(c) or std.ascii.isDigit(c);
}

fn makeToken(lexer: *Lexer, lexeme: Lexeme, len: usize) Token {
    const location = Location{
        .name = lexer.source.name,
        .start = lexer.poses[lexer.cursor],
        .end = lexer.poses[lexer.cursor + len],
        .lines = lexer.source.lines,
    };
    lexer.cursor += len;
    return .{ .lexeme = lexeme, .location = location };
}

fn deinit(lexer: Lexer, gpa: std.mem.Allocator) void {
    gpa.free(lexer.poses);
}
