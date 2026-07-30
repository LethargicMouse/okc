const std = @import("std");

const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;

const ErrMsgs = struct {
    inner: std.ArrayList([]const u8),

    pub fn format(err_msgs: ErrMsgs, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("     expected:");
        for (err_msgs.inner.items) |msg| {
            try writer.print("\n       - {s}", .{msg});
        }
    }

    const empty: ErrMsgs = .{ .inner = .empty };

    fn append(err_msgs: *ErrMsgs, gpa: std.mem.Allocator, msg: []const u8) !void {
        try err_msgs.inner.append(gpa, msg);
    }

    fn clearRetainingCapacity(err_msgs: *ErrMsgs) void {
        err_msgs.inner.clearRetainingCapacity();
    }

    fn deinit(err_msgs: *ErrMsgs, gpa: std.mem.Allocator) void {
        err_msgs.inner.deinit(gpa);
    }
};

const Parser = @This();

gpa: std.mem.Allocator,
tokens: []const Lexer.Token,
arena: std.heap.ArenaAllocator,
err_msgs: ErrMsgs = .empty,
strs: std.ArrayList([]const u8) = .empty,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(gpa: std.mem.Allocator, tokens: []const Lexer.Token) Parser {
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .gpa = gpa,
        .tokens = tokens,
        .arena = arena,
    };
}

pub fn run(parser: *Parser) !Ast {
    defer parser.deinit();
    const res = try parser.parseMaybe(Ast, parseAst) orelse {
        std.log.err("failed to parse {f}\n{f}\n     found {s}", .{
            parser.tokens[parser.err_cursor].location,
            parser.err_msgs,
            parser.tokens[parser.err_cursor].lexeme.describe(),
        });
        return error.Handled;
    };
    return res;
}

fn parseAst(parser: *Parser) !Ast {
    const ext_funs = try parser.parseMany(Ast.ExtFun, parseExtFunLoud);
    const funs = try parser.parseMany(Ast.Fun, parseFunLoud);
    try parser.expectLoud(.eof);
    const strs = try parser.arena.allocator().alloc([]const u8, parser.strs.items.len);
    @memcpy(strs, parser.strs.items);
    return .{
        .funs = funs,
        .ext_funs = ext_funs,
        .strs = strs,
        .arena = parser.arena,
    };
}

fn parseExtFunLoud(parser: *Parser) !Ast.ExtFun {
    try parser.expectLoud(.ext);
    const header = try parser.parseHeaderLoud();
    try parser.expectLoud(.semi);
    return .{
        .header = header,
    };
}

fn parseHeaderLoud(parser: *Parser) !Ast.Header {
    try parser.expectLoud(.fun);
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.parl);
    const params = try parser.parseMany(Ast.Param, parseParamLoud);
    try parser.expectLoud(.parr);
    const ret_typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .params = params,
        .ret_typ = ret_typ,
    };
}

fn parseParamLoud(parser: *Parser) !Ast.Param {
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.colon);
    const typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .typ = typ,
    };
}

fn parseTypLoud(parser: *Parser) ParseError!Ast.Typ {
    return parser.parseEither(Ast.Typ, .{
        parseVerbalTyp,
        parsePtrTyp,
    }) catch |err| {
        try parser.fail("<type>");
        return err;
    };
}

fn parseEither(parser: *Parser, typ: type, comptime parses: anytype) !typ {
    inline for (parses) |parse| {
        if (try parser.parseMaybe(typ, parse)) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

fn parsePtrTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.amp);
    const typ = try parser.arena.allocator().create(Ast.Typ);
    typ.* = try parser.parseTypLoud();
    return .{ .ptr = typ };
}

fn parseVerbalTyp(parser: *Parser) !Ast.Typ {
    const name = try parser.parseName();
    return Ast.Typ.fromName(name);
}

fn parseMany(parser: *Parser, typ: type, comptime parse: fn (*Parser) ParseError!typ) ![]const typ {
    var vec = std.ArrayList(typ).empty;
    defer vec.deinit(parser.gpa);
    while (try parser.parseMaybe(typ, parse)) |item| {
        try vec.append(parser.gpa, item);
    }
    const slice = try parser.arena.allocator().alloc(typ, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseMaybe(parser: *Parser, typ: type, comptime parse: fn (*Parser) ParseError!typ) !?typ {
    const cursor_before = parser.cursor;
    const res = parse(parser) catch |err| switch (err) {
        error.ParseFailed => {
            parser.cursor = cursor_before;
            return null;
        },
        else => return err,
    };
    return res;
}

fn parseFunLoud(parser: *Parser) !Ast.Fun {
    const header = try parser.parseHeaderLoud();
    try parser.expectLoud(.curl);
    const statements = try parser.parseMany(Ast.Statement, parseStatementLoud);
    try parser.expectLoud(.curr);
    return .{
        .header = header,
        .statements = statements,
    };
}

fn parseStatementLoud(parser: *Parser) !Ast.Statement {
    return parser.parseEither(Ast.Statement, .{
        parseRetStatement,
        parseCallStatement,
    }) catch |err| {
        try parser.fail("<statement>");
        return err;
    };
}

fn parseCallStatement(parser: *Parser) !Ast.Statement {
    const call = try parser.parseCall();
    try parser.expectLoud(.semi);
    return .{ .call = call };
}

fn parseCall(parser: *Parser) !Ast.Call {
    const name = try parser.parseName();
    try parser.expectLoud(.parl);
    const args = try parser.parseMany(Ast.Expr, parseExprLoud);
    try parser.expectLoud(.parr);
    return .{
        .name = name,
        .args = args,
    };
}

fn parseRetStatement(parser: *Parser) !Ast.Statement {
    try parser.expect(.ret);
    const expr = try parser.parseExprLoud();
    try parser.expectLoud(.semi);
    return .{ .ret = expr };
}

fn parseExprLoud(parser: *Parser) !Ast.Expr {
    return parser.parseEither(Ast.Expr, .{
        parseIntExpr,
        parseStrExpr,
    }) catch |err| {
        try parser.fail("<expr>");
        return err;
    };
}

fn parseStrExpr(parser: *Parser) !Ast.Expr {
    const str = try parser.parseStr();
    const index = parser.strs.items.len;
    try parser.strs.append(parser.gpa, str);
    return .{ .str = index };
}

fn parseIntExpr(parser: *Parser) !Ast.Expr {
    const int = try parser.parseInt();
    return .{ .int = int };
}

fn parseNameLoud(parser: *Parser) ![]const u8 {
    return parser.parseName() catch |err| {
        try parser.fail("<name>");
        return err;
    };
}

fn parseName(parser: *Parser) ![]const u8 {
    return parser.parseLexeme(.name);
}

fn parseInt(parser: *Parser) ![]const u8 {
    return parser.parseLexeme(.int);
}

fn parseStr(parser: *Parser) ![]const u8 {
    return parser.parseLexeme(.str);
}

fn parseLexeme(parser: *Parser, comptime tag: @typeInfo(Lexeme).@"union".tag_type.?) ![]const u8 {
    const next = parser.tokens[parser.cursor].lexeme;
    if (next == tag) {
        parser.cursor += 1;
        return @field(next, @tagName(tag));
    }
    return error.ParseFailed;
}

fn deinit(parser: *Parser) void {
    parser.gpa.free(parser.tokens);
    parser.err_msgs.deinit(parser.gpa);
    parser.strs.deinit(parser.gpa);
}

fn expectLoud(parser: *Parser, lexeme: Lexeme) !void {
    parser.expect(lexeme) catch |err| {
        try parser.fail(lexeme.describe());
        return err;
    };
}

fn expect(parser: *Parser, lexeme: Lexeme) !void {
    if (parser.tokens[parser.cursor].lexeme.eq(lexeme)) {
        parser.cursor += 1;
    } else {
        return error.ParseFailed;
    }
}

fn fail(parser: *Parser, msg: []const u8) !void {
    switch (std.math.order(parser.cursor, parser.err_cursor)) {
        .lt => {},
        .eq => {
            try parser.err_msgs.append(parser.gpa, msg);
        },
        .gt => {
            parser.err_msgs.clearRetainingCapacity();
            try parser.err_msgs.append(parser.gpa, msg);
            parser.err_cursor = parser.cursor;
        },
    }
}

const ParseError = error{ ParseFailed, OutOfMemory };
