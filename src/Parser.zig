const std = @import("std");

const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;
const Location = @import("Location.zig");
const Memo = @import("memo.zig").Memo;

const ExprStatementPostfix = union(enum) {
    assign: Ast.Expr,
    op_assign: OpAssignPostfix,
    none,
};

const OpAssignPostfix = struct {
    kind: Ast.Expr.Binary.Kind,
    expr: Ast.Expr,
};

const BinPostfix = struct {
    kind: Ast.Expr.Binary.Kind,
    expr: Ast.Expr,
};

const Postfix = union(enum) {
    const Elem = struct {
        index: Ast.Expr,
        location: Location,
    };

    const Field = struct {
        name: []const u8,
        location: Location,
    };

    field: Field,
    elem: Elem,
};

const ErrMsgs = struct {
    inner: std.ArrayList([]const u8),

    pub fn format(err_msgs: ErrMsgs, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (err_msgs.inner.items.len == 1) {
            try writer.print("     expected  {s}", .{err_msgs.inner.items[0]});
            return;
        }
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
        err_msgs.* = undefined;
    }
};

const Parser = @This();

gpa: std.mem.Allocator,
tokens: []const Lexer.Token,
ast_arena: *std.heap.ArenaAllocator,
ast_typ_memo: *Memo(Ast.Typ),
err_msgs: ErrMsgs = .empty,
tmp_location: Location = .fake,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(
    gpa: std.mem.Allocator,
    ast_arena: *std.heap.ArenaAllocator,
    ast_typ_memo: *Memo(Ast.Typ),
    tokens: []const Lexer.Token,
) Parser {
    return .{
        .gpa = gpa,
        .ast_arena = ast_arena,
        .ast_typ_memo = ast_typ_memo,
        .tokens = tokens,
    };
}

pub fn run(parser: *Parser) !Ast {
    defer parser.deinit();
    const ast = try parser.parseMaybe(Ast, parseAst) orelse {
        std.log.err("failed to parse {f}\n{f}\n        found  {s}", .{
            parser.tokens[parser.err_cursor].location,
            parser.err_msgs,
            parser.tokens[parser.err_cursor].lexeme.describe(),
        });
        if (parser.err_cursor != 0) {
            const before = parser.tokens[parser.err_cursor - 1];
            if (before.lexeme == .name and std.mem.eql(u8, before.lexeme.name, "else")) {
                std.log.info("use `or` instead of `else`", .{});
            }
        }
        return error.Handled;
    };
    return ast;
}

fn parseAst(parser: *Parser) !Ast {
    const items = try parser.parseMany(Ast.Item, parseItemLoud);
    const location = parser.getLocation();
    try parser.expect(.eof);
    return .{
        .items = items,
        .location = location,
    };
}

fn parseItemLoud(parser: *Parser) !Ast.Item {
    return parser.parseEither(Ast.Item, &.{
        parseFunItem,
        parseStructItem,
        parseExtFunItem,
        parseConstantItem,
    }) catch |err| {
        try parser.fail("<item>");
        return err;
    };
}

fn parseConstantItem(parser: *Parser) !Ast.Item {
    try parser.expect(.let);
    const location = parser.getLocation();
    const declare = try parser.parseDeclareLoud();
    return .{
        .location = location,
        .kind = .{ .constant = declare },
    };
}

fn parseExtFunItem(parser: *Parser) !Ast.Item {
    const ext_fun = try parser.parseExtFun();
    return .{
        .location = parser.tmp_location,
        .kind = .{ .ext_fun = ext_fun },
    };
}

fn parseFunItem(parser: *Parser) !Ast.Item {
    const fun = try parser.parseFun();
    return .{
        .location = parser.tmp_location,
        .kind = .{ .fun = fun },
    };
}

fn parseStructItem(parser: *Parser) !Ast.Item {
    const struc = try parser.parseStruct();
    return .{
        .location = parser.tmp_location,
        .kind = .{ .struc = struc },
    };
}

fn parseStruct(parser: *Parser) !Ast.Struct {
    try parser.expect(.struc);
    parser.tmp_location = parser.getLocation();
    const name = try parser.parseNameLoud();
    const generics = try parser.parseMaybe([]const Ast.Generic, parseGenerics) orelse &.{};
    try parser.expectLoud(.curl);
    const fields = try parser.parseSep(Ast.FieldDecl, parseFieldDeclLoud);
    try parser.expect(.curr);
    return .{
        .name = name,
        .generics = generics,
        .fields = fields,
    };
}

fn parseGenerics(parser: *Parser) ![]const Ast.Generic {
    try parser.expect(.les);
    const res = try parser.parseSep(Ast.Generic, parseGenericLoud);
    try parser.expect(.mor);
    return res;
}

fn parseGenericLoud(parser: *Parser) !Ast.Generic {
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    return .{
        .name = name,
        .location = location,
    };
}

fn parseFieldDeclLoud(parser: *Parser) !Ast.FieldDecl {
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.colon);
    const typ = try parser.parseTypLoud();
    const default = try parser.parseMaybe(Ast.Expr, parseAssignPostfix);
    return .{
        .name = name,
        .typ = typ,
        .location = location,
        .default = default,
    };
}

fn parseExtFun(parser: *Parser) !Ast.ExtFun {
    try parser.expect(.ext);
    const header = try parser.parseHeaderLoud();
    try parser.expectLoud(.semi);
    return .{
        .header = header,
    };
}

fn parseHeaderLoud(parser: *Parser) !Ast.Header {
    const header = try parser.parseMaybe(Ast.Header, parseHeader);
    return header orelse {
        try parser.fail("`fn`");
        return error.ParseFailed;
    };
}

fn parseHeader(parser: *Parser) !Ast.Header {
    try parser.expect(.fun);
    parser.tmp_location = parser.getLocation();
    const name = try parser.parseNameLoud();
    const generics = try parser.parseMaybe([]const Ast.Generic, parseGenerics) orelse &.{};
    try parser.expectLoud(.parl);
    const params = try parser.parseSep(Ast.Param, parseParamLoud);
    try parser.expect(.parr);
    const ret_typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .generics = generics,
        .params = params,
        .ret_typ = ret_typ,
    };
}

fn parseSep(parser: *Parser, T: type, parse: fn (*Parser) Error!T) ![]T {
    var vec = std.ArrayList(T).empty;
    defer vec.deinit(parser.gpa);
    if (try parser.parseMaybe(T, parse)) |first| {
        try vec.append(parser.gpa, first);
        while (true) {
            parser.expectLoud(.comma) catch break;
            if (try parser.parseMaybe(T, parse)) |item| {
                try vec.append(parser.gpa, item);
            } else break;
        }
    }
    const slice = try parser.ast_arena.allocator().alloc(T, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseParamLoud(parser: *Parser) !Ast.Param {
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.colon);
    const typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .typ = typ,
        .location = location,
    };
}

fn parseTypLoud(parser: *Parser) Error!Ast.Typ {
    return parser.parseEither(Ast.Typ, .{
        parseFunTyp,
        parseGenericTyp,
        parseVerbalTyp,
        parseMutPtrTyp,
        parsePtrTyp,
        parseArrayTyp,
        parseSliceTyp,
    }) catch |err| {
        try parser.fail("<type>");
        return err;
    };
}

fn parseFunTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.fun);
    try parser.expectLoud(.parl);
    const params = try parser.parseSep(Ast.Typ, parseTypLoud);
    try parser.expect(.parr);
    const ret_typ = try parser.parseTypLoud();
    const ptr = try parser.ast_typ_memo.box(ret_typ);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

fn parseSliceTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.bral);
    try parser.expectLoud(.brar);
    var mutable = true;
    parser.expect(.mut) catch |err| switch (err) {
        error.ParseFailed => mutable = false,
    };
    const typ = try parser.parseTypLoud();
    const ptr = try parser.ast_typ_memo.box(typ);
    return .{ .slice = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

fn parseGenericTyp(parser: *Parser) !Ast.Typ {
    const location = parser.getLocation();
    const name = try parser.parseName();
    try parser.expect(.les);
    const generics = try parser.parseSep(Ast.Typ, parseTypLoud);
    try parser.expect(.mor);
    return .{ .name = .{
        .name = name,
        .generics = generics,
        .location = location,
    } };
}

fn parseArrayTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.bral);
    const len = try parser.parseInt();
    try parser.expectLoud(.brar);
    const typ = try parser.parseTypLoud();
    const ptr = try parser.ast_typ_memo.box(typ);
    return .{ .array = .{
        .len = len,
        .typ = ptr,
    } };
}

fn parseEither(parser: *Parser, typ: type, comptime parses: anytype) !typ {
    inline for (parses) |parse| {
        if (try parser.parseMaybe(typ, parse)) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

fn parseMutPtrTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.amp);
    try parser.expect(.mut);
    const typ = try parser.parseTypLoud();
    const ptr = try parser.ast_typ_memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = true,
    } };
}

fn parsePtrTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.amp);
    const typ = try parser.parseTypLoud();
    const ptr = try parser.ast_typ_memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = false,
    } };
}

fn parseVerbalTyp(parser: *Parser) !Ast.Typ {
    const location = parser.getLocation();
    const name = try parser.parseName();
    return Ast.Typ.fromName(name, location);
}

fn parseMany(parser: *Parser, T: type, parse: fn (*Parser) Error!T) ![]T {
    var vec = std.ArrayList(T).empty;
    defer vec.deinit(parser.gpa);
    while (try parser.parseMaybe(T, parse)) |item| {
        try vec.append(parser.gpa, item);
    }
    const slice = try parser.ast_arena.allocator().alloc(T, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseMaybe(parser: *Parser, T: type, parse: fn (*Parser) Error!T) !?T {
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

fn parseFun(parser: *Parser) !Ast.Fun {
    const header = try parser.parseHeader();
    const location = parser.tmp_location;
    const block = try parser.parseBlockLoud();
    parser.tmp_location = location;
    return .{
        .header = header,
        .body = block,
    };
}

fn parseBlockLoud(parser: *Parser) Error![]Ast.Statement {
    try parser.expectLoud(.curl);
    const statements = try parser.parseMany(Ast.Statement, parseStatementLoud);
    try parser.expect(.curr);
    return statements;
}

fn parseStatementLoud(parser: *Parser) !Ast.Statement {
    return parser.parseEither(Ast.Statement, .{
        parseUnreachableStatement,
        parseBreakStatement,
        parseRetStatement,
        parseDeclareStatement,
        parseMutDeclareStatement,
        parseIfStatement,
        parseWhileStatement,
        parseIgnoreStatement,
        parseExprStatement,
    }) catch |err| {
        try parser.fail("<statement>");
        return err;
    };
}

fn parseUnreachableStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.unre);
    try parser.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .unre,
    };
}

fn parseBreakStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.brek);
    try parser.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .brek,
    };
}

fn parseOpAssignStatementPostfix(
    parser: *Parser,
) !ExprStatementPostfix {
    const kind = try parser.parseOpAssignBinOp();
    try parser.expect(.equ);
    const expr = try parser.parseExprLoud();
    return .{ .op_assign = .{
        .kind = kind,
        .expr = expr,
    } };
}

fn parseOpAssignBinOp(parser: *Parser) !Ast.Expr.Binary.Kind {
    const res = Ast.Expr.Binary.Kind.fromLexeme(parser.tokens[parser.cursor].lexeme) orelse
        return error.ParseFailed;
    if (res.getClass() != .arith) {
        return error.ParseFailed;
    }
    parser.cursor += 1;
    return res;
}

fn parseIgnoreStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.wild);
    try parser.expectLoud(.equ);
    const expr = try parser.parseExprLoud();
    try parser.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .{ .ignore = .{
            .expr = expr,
        } },
    };
}

fn parseWhileStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.whi);
    const branch = try parser.parseBranch();
    return .{ .location = location, .kind = .{ .whi = .{ .branch = branch } } };
}

fn parseIfStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.iff);
    const branch = try parser.parseBranch();
    const else_ifs = try parser.parseMany(Ast.Branch, parseElseIf);
    const else_branch = try parser.parseMaybe([]Ast.Statement, parseElseLoud) orelse @constCast(&.{});
    return .{
        .location = location,
        .kind = .{ .iff = .{
            .branch = branch,
            .else_ifs = else_ifs,
            .else_branch = else_branch,
        } },
    };
}

fn parseElseIf(parser: *Parser) !Ast.Branch {
    try parser.expect(.els);
    try parser.expect(.iff);
    const branch = try parser.parseBranch();
    return branch;
}

fn parseBranch(parser: *Parser) !Ast.Branch {
    try parser.expectLoud(.parl);
    const condition = try parser.parseExprLoud();
    try parser.expectLoud(.parr);
    const statements = try parser.parseBlockLoud();
    return .{
        .condition = condition,
        .body = statements,
    };
}

fn parseElseLoud(parser: *Parser) ![]Ast.Statement {
    try parser.expectLoud(.els);
    const statements = try parser.parseBlockLoud();
    return statements;
}

fn parseAssignStatementPostfix(parser: *Parser) !ExprStatementPostfix {
    const expr = try parser.parseAssignPostfix();
    return .{ .assign = expr };
}

fn parseAssignPostfix(parser: *Parser) !Ast.Expr {
    try parser.expect(.equ);
    return parser.parseExprLoud();
}

fn parseDeclareStatement(parser: *Parser) !Ast.Statement {
    try parser.expect(.let);
    const location = parser.getLocation();
    const declare = try parser.parseDeclareLoud();
    return .{
        .location = location,
        .kind = .{ .declare = declare },
    };
}

fn parseMutDeclareStatement(parser: *Parser) !Ast.Statement {
    try parser.expect(.let);
    try parser.expect(.mut);
    const location = parser.getLocation();
    const declare = try parser.parseDeclareLoud();
    return .{
        .location = location,
        .kind = .{ .mut_declare = declare },
    };
}

fn parseDeclareLoud(parser: *Parser) !Ast.Declare {
    const name = try parser.parseNameLoud();
    const typ = try parser.parseMaybe(Ast.Typ, parseTypAnnotLoud);
    try parser.expectLoud(.equ);
    const expr = try parser.parseExprLoud();
    try parser.expectLoud(.semi);
    return .{
        .name = name,
        .typ = typ,
        .expr = expr,
    };
}

fn parseTypAnnotLoud(parser: *Parser) !Ast.Typ {
    try parser.expectLoud(.colon);
    const typ = try parser.parseTypLoud();
    return typ;
}

fn parseExprStatement(parser: *Parser) !Ast.Statement {
    const expr = try parser.parseExpr();
    const postfix = try parser.parseExprStatementPostfix();
    try parser.expectLoud(.semi);
    switch (postfix) {
        .none => return .{ .location = expr.location, .kind = .{ .expr = expr } },
        .assign => |right| {
            return .{
                .location = expr.location.combine(right.location),
                .kind = .{ .assign = .{
                    .left = expr,
                    .expr = right,
                } },
            };
        },
        .op_assign => |op_assign| {
            const location = expr.location.combine(op_assign.expr.location);
            return .{
                .location = location,
                .kind = .{ .op_assign = .{
                    .left = expr,
                    .kind = op_assign.kind,
                    .right = op_assign.expr,
                } },
            };
        },
    }
}

fn parseExprStatementPostfix(parser: *Parser) !ExprStatementPostfix {
    return parser.parseEither(ExprStatementPostfix, &.{
        parseAssignStatementPostfix,
        parseOpAssignStatementPostfix,
    }) catch .none;
}

fn parseCall(parser: *Parser) !Ast.Expr.Call {
    const name = try parser.parseName();
    try parser.expect(.parl);
    const args = try parser.parseSep(Ast.Expr, parseExprLoud);
    try parser.expect(.parr);
    return .{
        .name = name,
        .args = args,
    };
}

fn parseRetStatement(parser: *Parser) !Ast.Statement {
    const location = parser.getLocation();
    try parser.expect(.ret);
    const expr = try parser.parseMaybe(Ast.Expr, parseExprLoud);
    try parser.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .{ .ret = .{
            .expr = expr,
        } },
    };
}

fn parseExprLoud(parser: *Parser) !Ast.Expr {
    const expr = try parser.parseMaybe(Ast.Expr, parseExpr);
    return expr orelse {
        try parser.fail("<expr>");
        return error.ParseFailed;
    };
}

fn parseExpr(parser: *Parser) !Ast.Expr {
    return parser.parseExprPrior(0, false);
}

fn parseExprPrior(parser: *Parser, prior: u8, loud: bool) Error!Ast.Expr {
    var res = try parser.parseExprPosted(loud);
    while (try parser.parseBinPostfix(prior)) |bin_postfix| {
        const binary = try parser.ast_arena.allocator().create(Ast.Expr.Binary);
        binary.* = .{
            .left = res,
            .kind = bin_postfix.kind,
            .right = bin_postfix.expr,
        };
        res = .{
            .location = res.location.combine(bin_postfix.expr.location),
            .kind = .{ .binary = binary },
        };
    }
    return res;
}

fn parseBinPostfix(parser: *Parser, prior: u8) !?BinPostfix {
    const cursor_before = parser.cursor;
    const kind = parser.parseBinOp(prior) orelse return null;
    const expr = parser.parseExprPrior(kind.getPrior() + 1, true) catch |err| switch (err) {
        error.ParseFailed => {
            parser.cursor = cursor_before;
            return null;
        },
        else => return err,
    };
    return .{
        .kind = kind,
        .expr = expr,
    };
}

fn parseBinOp(parser: *Parser, prior: u8) ?Ast.Expr.Binary.Kind {
    const res = Ast.Expr.Binary.Kind.fromLexeme(parser.tokens[parser.cursor].lexeme) orelse
        return null;
    if (res.getPrior() < prior) {
        return null;
    }
    parser.cursor += 1;
    return res;
}

fn parseExprPostedLoud(parser: *Parser) Error!Ast.Expr {
    return parser.parseExprPosted(true);
}

fn parseExprPosted(parser: *Parser, loud: bool) Error!Ast.Expr {
    var res = try parser.parseExprAtom(loud);
    while (try parser.parseMaybe(Postfix, parsePostfix)) |postfix| {
        switch (postfix) {
            .field => |field_postfix| {
                const field = try parser.ast_arena.allocator().create(Ast.Expr.Field);
                field.* = .{
                    .expr = res,
                    .name = field_postfix.name,
                };
                res = .{
                    .location = res.location.combine(field_postfix.location),
                    .kind = .{ .field = field },
                };
            },
            .elem => |elem_postfix| {
                const elem = try parser.ast_arena.allocator().create(Ast.Expr.Elem);
                elem.expr = res;
                elem.index = elem_postfix.index;
                res = .{
                    .location = res.location.combine(elem_postfix.location),
                    .kind = .{ .elem = elem },
                };
            },
        }
    }
    return res;
}

fn parsePostfix(parser: *Parser) !Postfix {
    return parser.parseEither(Postfix, .{
        parseFieldPostfix,
        parseElemPostfix,
    });
}

fn parseElemPostfix(parser: *Parser) !Postfix {
    try parser.expect(.bral);
    const index = try parser.parseExprLoud();
    const location = parser.getLocation();
    try parser.expectLoud(.brar);
    return .{
        .elem = .{
            .index = index,
            .location = location,
        },
    };
}

fn parseFieldPostfix(parser: *Parser) !Postfix {
    try parser.expect(.dot);
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    return .{ .field = .{
        .name = name,
        .location = location,
    } };
}

fn getLocation(parser: Parser) Location {
    return parser.tokens[parser.cursor].location;
}

fn parseExprAtom(parser: *Parser, loud: bool) Error!Ast.Expr {
    return parser.parseEither(Ast.Expr, .{
        parseAtExpr,
        parseParExpr,
        parseArrayExpr,
        parseUnaryExpr,
        parseInferStructExpr,
        parseStructExpr,
        parseCallExpr,
        parseIntExpr,
        parseStrExpr,
        parseCharExpr,
        parseVarExpr,
        parseUndefinedExpr,
        parseTrueExpr,
    }) catch |err| {
        if (loud) {
            try parser.fail("<expr>");
        }
        return err;
    };
}

fn parseAtExpr(parser: *Parser) !Ast.Expr {
    const start = parser.getLocation();
    try parser.expect(.at);
    const name = try parser.parseNameLoud();
    if (std.mem.eql(u8, name, "sizeof")) {
        try parser.expectLoud(.les);
        const typ = try parser.parseTypLoud();
        const end = parser.getLocation();
        try parser.expectLoud(.mor);
        return .{
            .location = start.combine(end),
            .kind = .{ .sizeof = typ },
        };
    }
    return error.ParseFailed;
}

fn parseArrayExpr(parser: *Parser) !Ast.Expr {
    const start = parser.getLocation();
    const mtyp = try parser.parseMaybe(Ast.Typ, parseTypHint);
    try parser.expect(.bral);
    const exprs = try parser.parseSep(Ast.Expr, parseExprLoud);
    const end = parser.getLocation();
    try parser.expect(.brar);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .mtyp = mtyp,
        } },
    };
}

fn parseTypHint(parser: *Parser) !Ast.Typ {
    try parser.expect(.les);
    const typ = try parser.parseTypLoud();
    try parser.expectLoud(.mor);
    return typ;
}

fn parseUnaryExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const kind = try parser.parseUnaryOp();
    const expr = try parser.parseExprPostedLoud();
    const unary = try parser.ast_arena.allocator().create(Ast.Expr.Unary);
    unary.* = .{
        .kind = kind,
        .expr = expr,
    };
    return .{
        .location = location.combine(expr.location),
        .kind = .{ .unary = unary },
    };
}

fn parseUnaryOp(parser: *Parser) !Ast.Expr.Unary.Kind {
    const res = Ast.Expr.Unary.Kind.fromLexeme(parser.tokens[parser.cursor].lexeme) orelse
        return error.ParseFailed;
    parser.cursor += 1;
    return res;
}

fn parseInferStructExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    try parser.expect(.dot);
    const fields = try parser.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .struc = .{ .fields = fields } },
    };
}

fn parseParExpr(parser: *Parser) !Ast.Expr {
    const start = parser.getLocation();
    try parser.expect(.parl);
    var expr = try parser.parseExprLoud();
    try parser.expectLoud(.parr);
    const end = parser.getLocation();
    expr.location = start.combine(end);
    return expr;
}

fn parseStructExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const name = try parser.parseName();
    const fields = try parser.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .named_struc = .{
            .name = name,
            .struc = .{ .fields = fields },
        } },
    };
}

fn parseStructExprBody(parser: *Parser) ![]Ast.Expr.Struct.Field {
    try parser.expect(.curl);
    const fields = try parser.parseSep(Ast.Expr.Struct.Field, parseNewFieldLoud);
    try parser.expect(.curr);
    return fields;
}

fn parseNewFieldLoud(parser: *Parser) !Ast.Expr.Struct.Field {
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.equ);
    const expr = try parser.parseExprLoud();
    return .{
        .name = name,
        .expr = expr,
        .location = location,
    };
}

fn parseLitLocExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const literal = try parser.parseLiteral();
    return .{ .lit_loc = .{
        .literal = literal,
        .location = location,
    } };
}

fn parseVarExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const name = try parser.parseName();
    return .{
        .location = location,
        .kind = .{ .vari = name },
    };
}

fn parseCallExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const call = try parser.parseCall();
    return .{
        .location = location,
        .kind = .{ .call = call },
    };
}

fn parseStrExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const str = try parser.parseStr();
    return .{
        .location = location,
        .kind = .{ .str = str },
    };
}

fn parseUndefinedExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    try parser.expect(.undef);
    return .{
        .location = location,
        .kind = .{ .undef = .{} },
    };
}

fn parseTrueExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    try parser.expect(.tru);
    return .{
        .location = location,
        .kind = .{ .bool = true },
    };
}

fn parseCharExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const char = try parser.parseChar();
    return .{
        .location = location,
        .kind = .{ .char = char },
    };
}

fn parseIntExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const val = try parser.parseInt();
    return .{
        .location = location,
        .kind = .{ .int = .{ .val = val } },
    };
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

fn parseIntLoud(parser: *Parser) ![]const u8 {
    return parser.parseInt() catch |err| {
        try parser.fail("<int>");
        return err;
    };
}

fn parseInt(parser: *Parser) !u64 {
    return parser.parseLexeme(.int);
}

fn parseChar(parser: *Parser) !u8 {
    return parser.parseLexeme(.char);
}

fn parseStr(parser: *Parser) ![]const u8 {
    return parser.parseLexeme(.str);
}

fn parseLexeme(
    parser: *Parser,
    comptime tag: @typeInfo(Lexeme).@"union".tag_type.?,
) !std.meta.fieldInfo(Lexeme, tag).type {
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
    parser.* = undefined;
}

fn expectLoud(parser: *Parser, lexeme: Lexeme) !void {
    parser.expect(lexeme) catch |err| {
        try parser.fail(lexeme.describe());
        return err;
    };
}

fn expect(parser: *Parser, lexeme: @typeInfo(Lexeme).@"union".tag_type.?) !void {
    if (parser.tokens[parser.cursor].lexeme == lexeme) {
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
