const std = @import("std");

const okc = @import("okc");

source: okc.Source,
poses: []const okc.Pos,
cursor: usize = 0,

pub fn init(gpa: std.mem.Allocator, source: okc.Source) error{OutOfMemory}!@This() {
    const poses = try okc.Pos.makePoses(gpa, source.code);
    return .{
        .source = source,
        .poses = poses,
    };
}

pub fn lex(self: *@This(), gpa: std.mem.Allocator) error{OutOfMemory}![]const Token {
    defer self.deinit(gpa);
    var vec = std.ArrayList(Token).empty;
    errdefer vec.deinit(gpa);
    try self.populate(gpa, &vec);
    return vec.toOwnedSlice(gpa);
}

fn populate(self: *@This(), gpa: std.mem.Allocator, res: *std.ArrayList(Token)) !void {
    while (true) {
        const before_skip = self.cursor;
        self.skip();
        if (self.cursor == self.source.code.len) {
            // so that eof is right after last lexeme
            self.cursor = before_skip;
            try res.append(gpa, self.makeToken(.eof, 0));
            break;
        }
        if (self.lexNext()) |token| {
            try res.append(gpa, token);
            continue;
        }
        try res.append(gpa, self.makeToken(.invalid, 1));
        break;
    }
}

fn skip(self: *@This()) void {
    var dirty = true;
    while (dirty) {
        dirty = false;
        self.skipSpaces(&dirty);
        self.skipComment(&dirty);
    }
}

fn skipSpaces(self: *@This(), dirty: *bool) void {
    const spaces = self.takeWhile(std.ascii.isWhitespace);
    if (spaces.len > 0) {
        dirty.* = true;
        self.cursor += spaces.len;
    }
}

fn skipComment(self: *@This(), dirty: *bool) void {
    if (std.mem.startsWith(u8, self.getRest(), "//")) {
        dirty.* = true;
        while (self.cursor < self.source.code.len and self.source.code[self.cursor] != '\n') {
            self.cursor += 1;
        }
        if (self.cursor != self.source.code.len) {
            self.cursor += 1;
        }
    }
}

fn lexNext(self: *@This()) ?Token {
    return self.lexByList() orelse
        self.lexVerbal() orelse
        self.lexInt() orelse
        self.lexStr() orelse
        self.lexChar();
}

fn lexChar(self: *@This()) ?Token {
    const rest = self.getRest();
    if (std.mem.startsWith(u8, rest, "'")) {
        if (rest.len == 1) {
            return self.makeToken(.unclosed_char, 1);
        }
        const c = rest[1];
        if (c == '\\') {
            if (rest.len == 2) {
                return self.makeToken(.unclosed_char, 2);
            }
            const msc: ?u8 = switch (rest[2]) {
                'n' => '\n',
                else => null,
            };
            if (rest.len == 3 or rest[3] != '\'') {
                return self.makeToken(.unclosed_char, 3);
            }
            const special_char = msc orelse {
                return self.makeToken(.invalid_char, 4);
            };
            return self.makeToken(.{ .char = special_char }, 4);
        }
        return self.makeToken(.{ .char = c }, 3);
    }
    return null;
}

fn lexStr(self: *@This()) ?Token {
    if (self.source.code[self.cursor] != '"') {
        return null;
    }
    const start = self.cursor;
    self.cursor += 1;
    while (self.cursor < self.source.code.len and self.source.code[self.cursor] != '"') {
        self.cursor += 1;
    }
    if (self.cursor == self.source.code.len) {
        self.cursor = start;
        return self.makeToken(.unclosed_str, 1);
    }
    const end = self.cursor;
    self.cursor = start;
    const str = self.source.code[start + 1 .. end];
    return self.makeToken(.{ .str = str }, end + 1 - start);
}

fn lexInt(self: *@This()) ?Token {
    const res = self.takeWhile(std.ascii.isDigit);
    if (res.len == 0) {
        return null;
    }
    const int = std.fmt.parseInt(u64, res, 10) catch {
        return self.makeToken(.int_too_big, res.len);
    };
    return self.makeToken(.{ .int = int }, res.len);
}

fn lexVerbal(self: *@This()) ?Token {
    var res = self.lexName() orelse return null;
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
    .{ .str = "use", .lexeme = .use },
    .{ .str = "type", .lexeme = .typ },
    .{ .str = "false", .lexeme = .fals },
    .{ .str = "for", .lexeme = .forr },
    .{ .str = "unreachable", .lexeme = .unre },
    .{ .str = "break", .lexeme = .brek },
    .{ .str = "true", .lexeme = .tru },
    .{ .str = "undefined", .lexeme = .undef },
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

fn lexByList(self: *@This()) ?Token {
    inline for (lex_list) |pair| {
        if (std.mem.startsWith(u8, self.getRest(), pair.str)) {
            return self.makeToken(pair.lexeme, pair.str.len);
        }
    }
    return null;
}

const lex_list = [_]LexPair{
    .{ .str = "@", .lexeme = .att },
    .{ .str = ">=", .lexeme = .moreq },
    .{ .str = ">", .lexeme = .mor },
    .{ .str = "|", .lexeme = .pipe },
    .{ .str = "~", .lexeme = .tild },
    .{ .str = "]", .lexeme = .brar },
    .{ .str = "[", .lexeme = .bral },
    .{ .str = "..", .lexeme = .dot2 },
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

fn getRest(self: @This()) []const u8 {
    return self.source.code[self.cursor..];
}

fn lexName(self: *@This()) ?Token {
    const res = self.takeWhile(isNameChar);
    if (res.len != 0 and isNameFirstChar(res[0])) {
        return self.makeToken(.{ .name = res }, res.len);
    }
    return null;
}

fn takeWhile(self: @This(), predicate: fn (u8) bool) []const u8 {
    var i = self.cursor;
    while (i < self.source.code.len and predicate(self.source.code[i])) {
        i += 1;
    }
    return self.source.code[self.cursor..i];
}

fn isNameFirstChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isNameChar(c: u8) bool {
    return isNameFirstChar(c) or std.ascii.isDigit(c);
}

fn makeToken(self: *@This(), lexeme: okc.Lexeme, len: usize) Token {
    var location = okc.Location{
        .name = self.source.name,
        .start = self.poses[self.cursor],
        .end = self.poses[self.cursor + len],
        .lines = self.source.lines,
    };
    self.cursor += len;
    if (len == 0) {
        location.end.symbol += 1;
    }
    return .{ .lexeme = lexeme, .location = location };
}

fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(self.poses);
    self.* = undefined;
}

pub const Token = struct { lexeme: okc.Lexeme, location: okc.Location };

const LexPair = struct { str: []const u8, lexeme: okc.Lexeme };
