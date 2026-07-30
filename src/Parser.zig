const std = @import("std");

const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;

const BinPostfix = struct {
    bin_op: Ast.BinOp,
    expr: Ast.Expr,
};

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
        // arena is not passed to ast, freeing it
        parser.arena.deinit();
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
    const params = try parser.parseSep(Ast.Param, parseParamLoud);
    try parser.expectLoud(.parr);
    const ret_typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .params = params,
        .ret_typ = ret_typ,
    };
}

fn parseSep(parser: *Parser, typ: type, parse: fn (*Parser) Error!typ) ![]const typ {
    var vec = std.ArrayList(typ).empty;
    defer vec.deinit(parser.gpa);
    if (try parser.parseMaybe(typ, parse)) |first| {
        try vec.append(parser.gpa, first);
        while (true) {
            parser.expectLoud(.comma) catch break;
            if (try parser.parseMaybe(typ, parse)) |item| {
                try vec.append(parser.gpa, item);
            } else break;
        }
    }
    const slice = try parser.arena.allocator().alloc(typ, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
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

fn parseTypLoud(parser: *Parser) Error!Ast.Typ {
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

fn parseMany(parser: *Parser, typ: type, parse: fn (*Parser) Error!typ) ![]const typ {
    var vec = std.ArrayList(typ).empty;
    defer vec.deinit(parser.gpa);
    while (try parser.parseMaybe(typ, parse)) |item| {
        try vec.append(parser.gpa, item);
    }
    const slice = try parser.arena.allocator().alloc(typ, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseMaybe(parser: *Parser, typ: type, parse: fn (*Parser) Error!typ) !?typ {
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
    const statements = try parser.parseBlockLoud();
    return .{
        .header = header,
        .statements = statements,
    };
}

fn parseBlockLoud(parser: *Parser) Error![]const Ast.Statement {
    try parser.expectLoud(.curl);
    const statements = try parser.parseMany(Ast.Statement, parseStatementLoud);
    try parser.expectLoud(.curr);
    return statements;
}

fn parseStatementLoud(parser: *Parser) !Ast.Statement {
    return parser.parseEither(Ast.Statement, .{
        parseRetStatement,
        parseLetStatement,
        parseIfStatement,
        parseAssignStatement,
        parseCallStatement,
    }) catch |err| {
        try parser.fail("<statement>");
        return err;
    };
}

fn parseIfStatement(parser: *Parser) !Ast.Statement {
    try parser.expect(.iff);
    const condition = try parser.parseExprLoud();
    const then_branch = try parser.parseBlockLoud();
    const else_branch = try parser.parseMaybe([]const Ast.Statement, parseElseLoud) orelse &.{};
    return .{ .iff = .{
        .condition = condition,
        .then_branch = then_branch,
        .else_branch = else_branch,
    } };
}

fn parseElseLoud(parser: *Parser) ![]const Ast.Statement {
    try parser.expectLoud(.els);
    const statements = try parser.parseBlockLoud();
    return statements;
}

fn parseAssignStatement(parser: *Parser) !Ast.Statement {
    const name = try parser.parseName();
    try parser.expectLoud(.equ);
    const expr = try parser.parseExprLoud();
    try parser.expectLoud(.semi);
    return .{ .assign = .{
        .name = name,
        .expr = expr,
    } };
}

fn parseLetStatement(parser: *Parser) !Ast.Statement {
    try parser.expect(.let);
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.equ);
    const expr = try parser.parseExprLoud();
    try parser.expectLoud(.semi);
    return .{ .let = .{
        .name = name,
        .expr = expr,
    } };
}

fn parseCallStatement(parser: *Parser) !Ast.Statement {
    const call = try parser.parseCall();
    try parser.expectLoud(.semi);
    return .{ .call = call };
}

fn parseCall(parser: *Parser) !Ast.Call {
    const name = try parser.parseName();
    try parser.expect(.parl);
    const args = try parser.parseSep(Ast.Expr, parseExprLoud);
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
    return parser.parseExprPriorLoud(0);
}

fn parseExprPriorLoud(parser: *Parser, prior: u8) Error!Ast.Expr {
    var res = try parser.parseExprAtomLoud();
    while (try parser.parseBinPostfix(prior)) |bin_postfix| {
        const binary = try parser.arena.allocator().create(Ast.Binary);
        binary.* = .{
            .left = res,
            .op = bin_postfix.bin_op,
            .right = bin_postfix.expr,
        };
        res = .{ .binary = binary };
    }
    return res;
}

fn parseBinPostfix(parser: *Parser, prior: u8) !?BinPostfix {
    const cursor_before = parser.cursor;
    const bin_op = parser.parseBinOp(prior) catch |err| switch (err) {
        error.ParseFailed => return null,
        else => return err,
    };
    const expr = parser.parseExprPriorLoud(bin_op.prior() + 1) catch |err| switch (err) {
        error.ParseFailed => {
            parser.cursor = cursor_before;
            return null;
        },
        else => return err,
    };
    return .{
        .bin_op = bin_op,
        .expr = expr,
    };
}

fn parseBinOp(parser: *Parser, prior: u8) !Ast.BinOp {
    const res = try parser.parseEither(Ast.BinOp, .{
        parseAdd,
        parseSub,
        parseMul,
        parseDiv,
        parseEqu,
    });
    if (res.prior() < prior) {
        parser.cursor -= 1;
        return error.ParseFailed;
    }
    return res;
}

fn parseEqu(parser: *Parser) !Ast.BinOp {
    try parser.expect(.equ2);
    return .equ;
}

fn parseAdd(parser: *Parser) !Ast.BinOp {
    try parser.expect(.plus);
    return .add;
}

fn parseSub(parser: *Parser) !Ast.BinOp {
    try parser.expect(.minus);
    return .sub;
}

fn parseMul(parser: *Parser) !Ast.BinOp {
    try parser.expect(.star);
    return .mul;
}

fn parseDiv(parser: *Parser) !Ast.BinOp {
    try parser.expect(.slash);
    return .div;
}

fn parseExprAtomLoud(parser: *Parser) Error!Ast.Expr {
    return parser.parseEither(Ast.Expr, .{
        parseIntExpr,
        parseStrExpr,
        parseCallExpr,
        parseVarExpr,
    }) catch |err| {
        try parser.fail("<expr>");
        return err;
    };
}

fn parseVarExpr(parser: *Parser) !Ast.Expr {
    const name = try parser.parseName();
    return .{ .vari = name };
}

fn parseCallExpr(parser: *Parser) !Ast.Expr {
    const call = try parser.parseCall();
    return .{ .call = call };
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

const Error = error{ ParseFailed, OutOfMemory };
