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
err_msgs: ErrMsgs = .empty,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(gpa: std.mem.Allocator, tokens: []const Lexer.Token) Parser {
    return .{ .gpa = gpa, .tokens = tokens };
}

pub fn run(parser: *Parser) !Ast {
    defer parser.deinit();
    const res = try parser.parse_maybe(Ast, parse_ast) orelse {
        std.log.err("failed to parse {f}\n{f}", .{
            parser.tokens[parser.err_cursor].location,
            parser.err_msgs,
        });
        return error.Handled;
    };
    return res;
}

fn parse_ast(parser: *Parser) !Ast {
    const funs = try parser.parse_many(Ast.Fun, parse_fun_loud);
    try parser.expect_loud(.eof);
    return .{ .funs = funs };
}

fn parse_many(parser: *Parser, typ: type, parse: fn (*Parser) ParseError!typ) ![]const typ {
    var vec = std.ArrayList(typ).empty;
    while (try parser.parse_maybe(typ, parse)) |item| {
        try vec.append(parser.gpa, item);
    }
    return vec.toOwnedSlice(parser.gpa);
}

fn parse_maybe(parser: *Parser, typ: type, parse: fn (*Parser) ParseError!typ) !?typ {
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

fn parse_fun_loud(parser: *Parser) !Ast.Fun {
    try parser.expect_loud(.fun);
    const name = try parser.parse_name_loud();
    try parser.expect_loud(.parl);
    try parser.expect_loud(.parr);
    try parser.expect_loud(.{ .name = "i32" });
    try parser.expect_loud(.curl);
    const statements = try parser.parse_many(Ast.Statement, parse_statement_loud);
    try parser.expect_loud(.curr);
    return .{
        .name = name,
        .statements = statements,
    };
}

fn parse_statement_loud(parser: *Parser) !Ast.Statement {
    return parser.parse_ret_statement() catch |err| {
        try parser.fail("<statement>");
        return err;
    };
}

fn parse_ret_statement(parser: *Parser) !Ast.Statement {
    try parser.expect(.ret);
    const expr = try parser.parse_expr_loud();
    try parser.expect_loud(.semi);
    return .{ .ret = expr };
}

fn parse_expr_loud(parser: *Parser) !Ast.Expr {
    return parser.parse_int_expr() catch |err| {
        try parser.fail("<expr>");
        return err;
    };
}

fn parse_int_expr(parser: *Parser) !Ast.Expr {
    const int = try parser.parse_int();
    return .{ .int = int };
}

fn parse_name_loud(parser: *Parser) ![]const u8 {
    return parser.parse_name() catch |err| {
        try parser.fail("<name>");
        return err;
    };
}

fn parse_name(parser: *Parser) ![]const u8 {
    switch (parser.tokens[parser.cursor].lexeme) {
        .name => |name| {
            parser.cursor += 1;
            return name;
        },
        else => {
            return error.ParseFailed;
        },
    }
}

fn parse_int(parser: *Parser) ![]const u8 {
    switch (parser.tokens[parser.cursor].lexeme) {
        .int => |int| {
            parser.cursor += 1;
            return int;
        },
        else => {
            return error.ParseFailed;
        },
    }
}

fn deinit(parser: *Parser) void {
    parser.gpa.free(parser.tokens);
    parser.err_msgs.deinit(parser.gpa);
}

fn expect_loud(parser: *Parser, lexeme: Lexeme) !void {
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
