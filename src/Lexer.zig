const std = @import("std");

const Location = @import("Location.zig");
const Pos = @import("Pos.zig");
const Source = @import("Source.zig");

pub const Token = struct { lexeme: Lexeme, location: Location };

pub const Lexeme = union(enum) {
    name: []const u8,
    int: []const u8,
    str: []const u8,
    char: u8,
    moreq,
    mor,
    unre,
    brek,
    tru,
    undef,
    pipe,
    tild,
    bral,
    brar,
    struc,
    mut,
    wild,
    dot,
    els,
    rem,
    les,
    whi,
    iff,
    slash,
    minus,
    plus,
    equ2,
    equ,
    let,
    comma,
    unclosed_str,
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
    invalid,

    pub fn describe(lexeme: Lexeme) []const u8 {
        return switch (lexeme) {
            .moreq => "`>=`",
            .mor => "`>`",
            .unre => "`unreachable`",
            .brek => "`break`",
            .tru => "`true`",
            .undef => "`undefined`",
            .pipe => "`|`",
            .tild => "`~`",
            .bral => "`[`",
            .brar => "`]`",
            .struc => "`struct`",
            .mut => "`mut`",
            .wild => "`_`",
            .char => "<char>",
            .dot => "`.`",
            .els => "`else`",
            .rem => "`%`",
            .les => "`<`",
            .whi => "`while`",
            .equ2 => "`==`",
            .iff => "`if`",
            .slash => "`/`",
            .minus => "`-`",
            .plus => "`+`",
            .equ => "`=`",
            .let => "`let`",
            .comma => "`,`",
            .str => "<str>",
            .unclosed_str => "<unclosed string>",
            .name => "<name>",
            .int => "<int>",
            .ret => "`return`",
            .invalid => "<invalid>",
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
        };
    }
};

const LexPair = struct { str: []const u8, lexeme: Lexeme };

const Lexer = @This();

source: Source,
poses: []const Pos,
cursor: usize = 0,

pub fn init(gpa: std.mem.Allocator, source: Source) !Lexer {
    const poses = try Pos.makePoses(gpa, source.code);
    return .{
        .source = source,
        .poses = poses,
    };
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
        lexer.skip();
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
        try res.append(gpa, lexer.makeToken(.invalid, 1));
        break;
    }
}

fn skip(lexer: *Lexer) void {
    var dirty = true;
    while (dirty) {
        dirty = false;
        lexer.skipSpaces(&dirty);
        lexer.skipComment(&dirty);
    }
}

fn skipSpaces(lexer: *Lexer, dirty: *bool) void {
    const spaces = lexer.takeWhile(std.ascii.isWhitespace);
    if (spaces.len > 0) {
        dirty.* = true;
        lexer.cursor += spaces.len;
    }
}

fn skipComment(lexer: *Lexer, dirty: *bool) void {
    if (std.mem.startsWith(u8, lexer.getRest(), "//")) {
        dirty.* = true;
        while (lexer.cursor < lexer.source.code.len and lexer.source.code[lexer.cursor] != '\n') {
            lexer.cursor += 1;
        }
        if (lexer.cursor != lexer.source.code.len) {
            lexer.cursor += 1;
        }
    }
}

fn lexNext(lexer: *Lexer) ?Token {
    return lexer.lexByList() orelse lexer.lexVerbal() orelse lexer.lexInt() orelse lexer.lexStr() orelse lexer.lexChar();
}

fn lexChar(lexer: *Lexer) ?Token {
    const rest = lexer.getRest();
    if (rest.len >= 3 and rest[0] == '\'' and rest[0] == '\'') {
        return lexer.makeToken(.{ .char = rest[1] }, 3);
    }
    return null;
}

fn lexStr(lexer: *Lexer) ?Token {
    if (lexer.source.code[lexer.cursor] != '"') {
        return null;
    }
    const start = lexer.cursor;
    lexer.cursor += 1;
    while (lexer.cursor < lexer.source.code.len and lexer.source.code[lexer.cursor] != '"') {
        lexer.cursor += 1;
    }
    if (lexer.cursor == lexer.source.code.len) {
        lexer.cursor = start;
        return lexer.makeToken(.unclosed_str, 1);
    }
    const end = lexer.cursor;
    lexer.cursor = start;
    const str = lexer.source.code[start + 1 .. end];
    return lexer.makeToken(.{ .str = str }, end + 1 - start);
}

fn lexInt(lexer: *Lexer) ?Token {
    const res = lexer.takeWhile(std.ascii.isDigit);
    if (res.len == 0) {
        return null;
    }
    return lexer.makeToken(.{ .int = res }, res.len);
}

fn lexVerbal(lexer: *Lexer) ?Token {
    var res = lexer.lexName() orelse return null;
    const name = res.lexeme.name;
    inline for (verbal_list) |pair| {
        if (std.mem.eql(u8, name, pair.str)) {
            res.lexeme = pair.lexeme;
            break;
        }
    }
    return res;
}

const verbal_list = [_]LexPair{
    .{ .str = "unreachable", .lexeme = .unre },
    .{ .str = "break", .lexeme = .brek },
    .{ .str = "true", .lexeme = .tru },
    .{ .str = "undefined", .lexeme = .undef },
    .{ .str = "struct", .lexeme = .struc },
    .{ .str = "mut", .lexeme = .mut },
    .{ .str = "_", .lexeme = .wild },
    .{ .str = "else", .lexeme = .els },
    .{ .str = "while", .lexeme = .whi },
    .{ .str = "extern", .lexeme = .ext },
    .{ .str = "fn", .lexeme = .fun },
    .{ .str = "if", .lexeme = .iff },
    .{ .str = "let", .lexeme = .let },
    .{ .str = "return", .lexeme = .ret },
};

fn lexByList(lexer: *Lexer) ?Token {
    inline for (lex_list) |pair| {
        if (std.mem.startsWith(u8, lexer.getRest(), pair.str)) {
            return lexer.makeToken(pair.lexeme, pair.str.len);
        }
    }
    return null;
}

const lex_list = [_]LexPair{
    .{ .str = ">=", .lexeme = .moreq },
    .{ .str = ">", .lexeme = .mor },
    .{ .str = "|", .lexeme = .pipe },
    .{ .str = "~", .lexeme = .tild },
    .{ .str = "]", .lexeme = .brar },
    .{ .str = "[", .lexeme = .bral },
    .{ .str = ".", .lexeme = .dot },
    .{ .str = "%", .lexeme = .rem },
    .{ .str = "<", .lexeme = .les },
    .{ .str = "/", .lexeme = .slash },
    .{ .str = "-", .lexeme = .minus },
    .{ .str = "+", .lexeme = .plus },
    .{ .str = "==", .lexeme = .equ2 },
    .{ .str = "=", .lexeme = .equ },
    .{ .str = ",", .lexeme = .comma },
    .{ .str = "&", .lexeme = .amp },
    .{ .str = "*", .lexeme = .star },
    .{ .str = ":", .lexeme = .colon },
    .{ .str = ";", .lexeme = .semi },
    .{ .str = "(", .lexeme = .parl },
    .{ .str = ")", .lexeme = .parr },
    .{ .str = "{", .lexeme = .curl },
    .{ .str = "}", .lexeme = .curr },
};

fn getRest(lexer: Lexer) []const u8 {
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

fn deinit(lexer: *Lexer, gpa: std.mem.Allocator) void {
    gpa.free(lexer.poses);
    lexer.* = undefined;
}
