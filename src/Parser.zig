const std = @import("std");

const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;
const Location = @import("Location.zig");

const ExprStatementPostfix = union(enum) {
    assign: Ast.Expr,
    op_assign: OpAssignPostfix,
    none,
};

const OpAssignPostfix = struct {
    kind: Ast.Binary.Kind,
    expr: Ast.Expr,
};

const BinPostfix = struct {
    kind: Ast.Binary.Kind,
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
arena: std.heap.ArenaAllocator,
err_msgs: ErrMsgs = .empty,
strs: std.ArrayList([]const u8) = .empty,
cursor: usize = 0,
err_cursor: usize = 0,
next_typ_id: usize = 0,

pub fn init(gpa: std.mem.Allocator, tokens: []const Lexer.Token) Parser {
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .gpa = gpa,
        .tokens = tokens,
        .arena = arena,
    };
}

pub fn run(parser: *Parser) !struct { Ast, Ast.Info } {
    defer parser.deinit();
    const ast = try parser.parseMaybe(Ast, parseAst) orelse {
        // arena is not passed to ast, freeing it
        parser.arena.deinit();
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
    const ast_info = Ast.Info{
        .typ_ids = parser.next_typ_id,
    };
    return .{ ast, ast_info };
}

fn parseAst(parser: *Parser) !Ast {
    const items = try parser.parseMany(Ast.Item, parseItemLoud);
    const location = parser.getLocation();
    try parser.expectLoud(.eof);
    const strs = try parser.arena.allocator().alloc([]const u8, parser.strs.items.len);
    @memcpy(strs, parser.strs.items);
    return .{
        .arena = parser.arena,
        .items = items,
        .strs = strs,
        .location = location,
    };
}

fn parseItemLoud(parser: *Parser) !Ast.Item {
    return parser.parseEither(Ast.Item, &.{
        parseFunItem,
        parseStructItem,
        parseExtFunItem,
    }) catch |err| {
        try parser.fail("<item>");
        return err;
    };
}

fn parseExtFunItem(parser: *Parser) !Ast.Item {
    const ext_fun = try parser.parseExtFun();
    return .{ .ext_fun = ext_fun };
}

fn parseFunItem(parser: *Parser) !Ast.Item {
    const fun = try parser.parseFun();
    return .{ .fun = fun };
}

fn parseStructItem(parser: *Parser) !Ast.Item {
    const struc = try parser.parseStruct();
    return .{ .struc = struc };
}

fn parseStruct(parser: *Parser) !Ast.Struct {
    try parser.expect(.struc);
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.curl);
    const fields = try parser.parseSep(Ast.FieldDecl, parseFieldDeclLoud);
    try parser.expect(.curr);
    return .{
        .name = name,
        .fields = fields,
        .location = location,
    };
}

fn parseFieldDeclLoud(parser: *Parser) !Ast.FieldDecl {
    const param = try parser.parseParamLoud();
    return .{
        .name = param.name,
        .typ = param.typ,
        .location = param.location,
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
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.parl);
    const params = try parser.parseSep(Ast.Param, parseParamLoud);
    try parser.expect(.parr);
    const ret_typ = try parser.parseTypLoud();
    return .{
        .name = name,
        .params = params,
        .ret_typ = ret_typ,
        .location = location,
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
        parseVerbalTyp,
        parseMutPtrTyp,
        parsePtrTyp,
        parseArrayTyp,
    }) catch |err| {
        try parser.fail("<type>");
        return err;
    };
}

fn parseArrayTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.bral);
    const len = try parser.parseIntLoud();
    try parser.expectLoud(.brar);
    const typ = try parser.parseTypLoud();
    const array_typ = try parser.arena.allocator().create(Ast.Typ.Array);
    array_typ.len = len;
    array_typ.typ = typ;
    return .{ .array = array_typ };
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
    const ptr = try parser.arena.allocator().create(Ast.Typ);
    ptr.* = typ;
    return .{ .mut_ptr = ptr };
}

fn parsePtrTyp(parser: *Parser) !Ast.Typ {
    try parser.expect(.amp);
    const typ = try parser.parseTypLoud();
    const ptr = try parser.arena.allocator().create(Ast.Typ);
    ptr.* = typ;
    return .{ .ptr = ptr };
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

fn parseFun(parser: *Parser) !Ast.Fun {
    const header = try parser.parseHeader();
    const block = try parser.parseBlockLoud();
    return .{
        .header = header,
        .body = block,
    };
}

fn parseBlockLoud(parser: *Parser) Error![]const Ast.Statement {
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

fn parseOpAssignBinOp(parser: *Parser) !Ast.Binary.Kind {
    return parser.parseEither(Ast.Binary.Kind, &.{
        parseBitAnd,
    });
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
    const else_branch = try parser.parseMaybe([]const Ast.Statement, parseElseLoud) orelse &.{};
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

fn parseElseLoud(parser: *Parser) ![]const Ast.Statement {
    try parser.expectLoud(.els);
    const statements = try parser.parseBlockLoud();
    return statements;
}

fn parseAssignStatementPostfix(parser: *Parser) !ExprStatementPostfix {
    try parser.expect(.equ);
    const expr = try parser.parseExprLoud();
    return .{ .assign = expr };
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

fn parseCall(parser: *Parser) !Ast.Call {
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
        const binary = try parser.arena.allocator().create(Ast.Binary);
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
    const kind = parser.parseBinOp(prior) catch |err| switch (err) {
        error.ParseFailed => return null,
        else => return err,
    };
    const expr = parser.parseExprPrior(kind.prior() + 1, true) catch |err| switch (err) {
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

fn parseBinOp(parser: *Parser, prior: u8) !Ast.Binary.Kind {
    const res = try parser.parseEither(Ast.Binary.Kind, .{
        parseAdd,
        parseSub,
        parseMul,
        parseDiv,
        parseEqu,
        parseLes,
        parseRem,
        parseBitAnd,
        parseBitOr,
    });
    if (res.prior() < prior) {
        parser.cursor -= 1;
        return error.ParseFailed;
    }
    return res;
}

fn parseBitOr(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.pipe);
    return .orb;
}

fn parseBitAnd(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.amp);
    return .andb;
}

fn parseRem(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.rem);
    return .rem;
}

fn parseLes(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.les);
    return .les;
}

fn parseEqu(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.equ2);
    return .equ;
}

fn parseAdd(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.plus);
    return .add;
}

fn parseSub(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.minus);
    return .sub;
}

fn parseMul(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.star);
    return .mul;
}

fn parseDiv(parser: *Parser) !Ast.Binary.Kind {
    try parser.expect(.slash);
    return .div;
}

fn parseExprPostedLoud(parser: *Parser) Error!Ast.Expr {
    return parser.parseExprPosted(true);
}

fn parseExprPosted(parser: *Parser, loud: bool) Error!Ast.Expr {
    var res = try parser.parseExprAtom(loud);
    while (try parser.parseMaybe(Postfix, parsePostfix)) |postfix| {
        switch (postfix) {
            .field => |field_postfix| {
                const field = try parser.arena.allocator().create(Ast.Field);
                field.expr = res;
                field.name = field_postfix.name;
                res = .{
                    .location = field_postfix.location,
                    .kind = .{ .field = field },
                };
            },
            .elem => |elem_postfix| {
                const elem = try parser.arena.allocator().create(Ast.Elem);
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
        parseParExpr,
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

fn parseUnaryExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    const kind = try parser.parseUnaryOp();
    const expr = try parser.parseExprPostedLoud();
    const unary = try parser.arena.allocator().create(Ast.Unary);
    unary.* = .{
        .kind = kind,
        .expr = expr,
    };
    return .{
        .location = location.combine(expr.location),
        .kind = .{ .unary = unary },
    };
}

fn parseUnaryOp(parser: *Parser) !Ast.Unary.Kind {
    return parser.parseEither(Ast.Unary.Kind, &.{
        parseMutPtr,
        parsePtr,
        parseNotB,
        parseDeref,
    });
}

fn parseMutPtr(parser: *Parser) !Ast.Unary.Kind {
    try parser.expect(.amp);
    try parser.expect(.mut);
    return .mut_ptr;
}

fn parseDeref(parser: *Parser) !Ast.Unary.Kind {
    try parser.expect(.star);
    return .deref;
}

fn parsePtr(parser: *Parser) !Ast.Unary.Kind {
    try parser.expect(.amp);
    return .ptr;
}

fn parseNotB(parser: *Parser) !Ast.Unary.Kind {
    try parser.expect(.tild);
    return .notb;
}

fn parseInferStructExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    try parser.expect(.dot);
    const fields = try parser.parseStructExprBody();
    const typ_id = parser.newTypId();
    return .{
        .location = location,
        .kind = .{ .infer_struc = .{
            .fields = fields,
            .typ_id = typ_id,
        } },
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
        .kind = .{ .struc = .{
            .name = name,
            .fields = fields,
        } },
    };
}

fn parseStructExprBody(parser: *Parser) ![]const Ast.NewField {
    try parser.expect(.curl);
    const fields = try parser.parseSep(Ast.NewField, parseNewFieldLoud);
    try parser.expect(.curr);
    return fields;
}

fn parseNewFieldLoud(parser: *Parser) !Ast.NewField {
    const location = parser.getLocation();
    const name = try parser.parseNameLoud();
    try parser.expectLoud(.colon);
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
    const index = parser.strs.items.len;
    try parser.strs.append(parser.gpa, str);
    return .{
        .location = location,
        .kind = .{ .str = index },
    };
}

fn parseUndefinedExpr(parser: *Parser) !Ast.Expr {
    const location = parser.getLocation();
    try parser.expect(.undef);
    const typ_id = parser.newTypId();
    return .{
        .location = location,
        .kind = .{ .undef = .{
            .typ_id = typ_id,
        } },
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

fn newTypId(parser: *Parser) usize {
    parser.next_typ_id += 1;
    return parser.next_typ_id - 1;
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
    const int = try parser.parseInt();
    return .{
        .location = location,
        .kind = .{ .int = int },
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

fn parseInt(parser: *Parser) ![]const u8 {
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
    parser.strs.deinit(parser.gpa);
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
