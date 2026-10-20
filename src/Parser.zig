const std = @import("std");

const okc = @import("okc");

gpa: std.mem.Allocator,
tokens: []const okc.Lexer.Token,
arena: std.mem.Allocator,
err_msgs: std.ArrayList([]const u8) = .empty,
tmp_name: []const u8 = "<unknown>",
tmp_location: okc.Location = .fake,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    tokens: []const okc.Lexer.Token,
) @This() {
    return .{
        .gpa = gpa,
        .arena = arena,
        .tokens = tokens,
    };
}

pub fn run(self: *@This()) error{ OutOfMemory, Handled }!okc.Module {
    defer self.deinit();
    const module = try self.maybe(parseModule, .{}) orelse {
        std.log.err("failed to parse {f}\n{f}\n        found  {s}", .{
            self.tokens[self.err_cursor].location,
            ErrMsgsPrinter{ .msgs = self.err_msgs.items },
            okc.Lexeme.describe(self.tokens[self.err_cursor].lexeme),
        });
        if (self.err_cursor != 0) {
            const before = self.tokens[self.err_cursor - 1];
            if (before.lexeme == .name and std.mem.eql(u8, before.lexeme.name, "else")) {
                std.log.info("use `or` instead of `else`", .{});
            }
        }
        return error.Handled;
    };
    return module;
}

fn parseModule(self: *@This()) !okc.Module {
    const items = try self.many(parseItem, .{});
    const location = self.getLocation();
    std.debug.assert(location.start.line == location.end.line);
    try self.expect(.eof, .quiet);
    return .{
        .items = items,
        .location = location,
    };
}

fn parseItem(self: *@This()) Error!okc.Item {
    return self.either(.{
        parseFunItem,
        parseTypItem,
        parseExtFunItem,
        parseConstantItem,
        parseTypAliasItem,
        parseUseItem,
    }) catch |err| {
        try self.fail("<item>");
        return err;
    };
}

fn parseUseItem(self: *@This()) !okc.Item {
    try self.expect(.use, .quiet);
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .name = name,
        .kind = .use,
    };
}

fn parseTypAliasItem(self: *@This()) !okc.Item {
    try self.expect(.typ, .quiet);
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.equ, .loud);
    const typ = try self.parseTyp();
    try self.expect(.semi, .loud);
    return .{
        .name = name,
        .location = location,
        .kind = .{ .typ_alias = .{
            .typ = typ,
        } },
    };
}

fn parseConstantItem(self: *@This()) !okc.Item {
    const named = try self.parseDeclare();
    return .{
        .name = named.name,
        .location = self.tmp_location,
        .kind = .{ .constant = .{ .declare = named.bare } },
    };
}

fn parseExtFunItem(self: *@This()) !okc.Item {
    const ext_fun = try self.parseExtFun();
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .ext_fun = ext_fun },
    };
}

fn parseFunItem(self: *@This()) !okc.Item {
    const fun = try self.parseFun();
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .fun = fun },
    };
}

fn parseTypItem(self: *@This()) !okc.Item {
    const typ: okc.Item.Typ = try .parse(self);
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .typ = typ },
    };
}

pub fn parseGenerics(self: *@This()) ![]const okc.Item.Generic {
    try self.expect(.les, .quiet);
    const res = try self.sep(parseGeneric, .{});
    try self.expect(.mor, .loud);
    return res;
}

fn parseGeneric(self: *@This()) !okc.Item.Generic {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    return .{
        .name = name,
        .location = location,
    };
}

pub fn parseFieldDecl(self: *@This()) !okc.Item.Typ.Field {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.colon, .loud);
    const typ = try self.parseTyp();
    const default = try self.maybe(parseAssignPostfix, .{});
    return .{
        .name = name,
        .typ = typ,
        .location = location,
        .default = default,
    };
}

fn parseExtFun(self: *@This()) !okc.Item.Fun.Extern {
    try self.expect(.ext, .quiet);
    const header = try self.parseHeader(.loud);
    try self.expect(.semi, .loud);
    return .{
        .header = header,
    };
}

fn parseHeader(self: *@This(), mode: Mode) !okc.Item.Fun.Header {
    try self.expect(.fun, mode);
    self.tmp_location = self.getLocation();
    self.tmp_name = try self.parseName(.loud);
    const generics = try self.maybe(parseGenerics, .{}) orelse &.{};
    try self.expect(.parl, .loud);
    const params = try self.sep(parseParam, .{});
    try self.expect(.parr, .loud);
    const ret_typ = try self.parseTyp();
    return .{
        .generics = generics,
        .params = params,
        .ret_typ = ret_typ,
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
    const slice = try self.arena.dupe(ParseRes(parse, args), vec.items);
    return slice;
}

fn parseParam(self: *@This()) !okc.Item.Fun.Header.Param {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.colon, .loud);
    const typ = try self.parseTyp();
    return .{
        .name = name,
        .typ = typ,
        .location = location,
    };
}

fn parseTyp(self: *@This()) Error!okc.Typ {
    return self.either(.{
        parseFunTyp,
        parseGenericTyp,
        parseVerbalTyp,
        parsePtrTyp,
        parseArrayTyp,
        parseSliceTyp,
    }) catch |err| {
        try self.fail("<type>");
        return err;
    };
}

fn parseFunTyp(self: *@This()) Error!okc.Typ {
    try self.expect(.fun, .quiet);
    try self.expect(.parl, .loud);
    const params = try self.sep(parseTyp, .{});
    try self.expect(.parr, .loud);
    const ret_typ = try self.parseTyp();
    const ptr = try okc.Typ.memo.box(ret_typ, self.arena);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

fn parseSliceTyp(self: *@This()) !okc.Typ {
    try self.expect(.bral, .quiet);
    try self.expect(.brar, .loud);
    var mutable = true;
    try self.maybe(expect, .{ .mut, .quiet }) orelse {
        mutable = false;
    };
    const typ = try self.parseTyp();
    const ptr = try okc.Typ.memo.box(typ, self.arena);
    return .{ .slice = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

fn parseGenericTyp(self: *@This()) Error!okc.Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    try self.expect(.les, .quiet);
    const generics = try self.sep(parseTyp, .{});
    try self.expect(.mor, .loud);
    return .{ .loc_name = .{
        .bare = .{
            .name = name,
            .generics = generics,
        },
        .location = location,
    } };
}

fn parseArrayTyp(self: *@This()) !okc.Typ {
    try self.expect(.bral, .quiet);
    const len = try self.parseInt();
    try self.expect(.brar, .loud);
    const typ = try self.parseTyp();
    const ptr = try okc.Typ.memo.box(typ, self.arena);
    return .{ .array = .{
        .len = len,
        .typ = ptr,
    } };
}

pub fn either(self: *@This(), comptime parses: anytype) !ParseRes(parses[0], .{}) {
    inline for (parses) |parse| {
        if (try self.maybe(parse, .{})) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

fn parsePtrTyp(self: *@This()) Error!okc.Typ {
    try self.expect(.amp, .quiet);
    var mutable = false;
    if (try self.maybe(expect, .{ .mut, .quiet })) |_| {
        mutable = true;
    }
    const typ = try self.parseTyp();
    const ptr = try okc.Typ.memo.box(typ, self.arena);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

fn parseVerbalTyp(self: *@This()) Error!okc.Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    return okc.Typ.fromName(name, location);
}

pub fn many(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    while (try self.maybe(parse, args)) |item| {
        try vec.append(self.gpa, item);
    }
    const slice = try self.arena.dupe(ParseRes(parse, args), vec.items);
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

fn parseFun(self: *@This()) !okc.Item.Fun {
    const header = try self.parseHeader(.quiet);
    const location = self.tmp_location;
    const name = self.tmp_name;
    const body = try self.parseBlock();
    self.tmp_location = location;
    self.tmp_name = name;
    return .{
        .header = header,
        .body = body,
    };
}

pub fn parseBlock(self: *@This()) Error!okc.Stmt.Block {
    try self.expect(.curl, .loud);
    const stmts = try self.many(okc.Stmt.parse, .{});
    try self.expect(.curr, .quiet);
    return .{ .stmts = stmts };
}

pub fn parseUnreachableStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.unre, .quiet);
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .unre,
    };
}

pub fn parseBreakStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.brek, .quiet);
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .brek,
    };
}

fn parseOpAssignStmtPostfix(
    self: *@This(),
) !ExprStmtPostfix {
    const kind = try self.parseOpAssignBinOp();
    try self.expect(.equ, .quiet);
    const expr = try self.parseExpr(.loud);
    return .{ .op_assign = .{
        .kind = kind,
        .expr = expr,
    } };
}

fn parseOpAssignBinOp(self: *@This()) !okc.Expr.Binary.Kind {
    const res = okc.Expr.Binary.Kind.fromLexeme(self.tokens[self.cursor].lexeme) orelse
        return error.ParseFailed;
    if (res.getClass() != .arith) {
        return error.ParseFailed;
    }
    self.cursor += 1;
    return res;
}

pub fn parseIgnoreStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.wild, .quiet);
    try self.expect(.equ, .loud);
    const expr = try self.parseExpr(.loud);
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .{ .ignore = .{
            .expr = expr,
        } },
    };
}

pub fn parseForStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.whi, .quiet);
    try self.expect(.parl, .loud);
    const vari_location = self.getLocation();
    const vari = try self.parseName(.loud);
    try self.expect(.colon, .loud);
    const expr = try self.parseExpr(.loud);
    const mend = try self.maybe(parseRangeEnd, .{});
    try self.expect(.parr, .loud);
    const body = try self.parseBlock();
    if (mend) |end| {
        return .{
            .location = location,
            .kind = .{ .for_range = .{
                .vari = vari,
                .start = expr,
                .end = end,
                .body = body,
                .vari_location = vari_location,
            } },
        };
    }
    return .{
        .location = location,
        .kind = .{ .forr = .{
            .vari = vari,
            .expr = expr,
            .body = body,
            .vari_location = vari_location,
        } },
    };
}

fn parseRangeEnd(self: *@This()) !okc.Expr {
    try self.expect(.dot2, .quiet);
    return self.parseExpr(.loud);
}

pub fn parseWhileStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.whi, .quiet);
    const branch = try self.parseBranch();
    return .{ .location = location, .kind = .{ .whi = .{ .branch = branch } } };
}

pub fn parseIfStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.iff, .quiet);
    const branch = try self.parseBranch();
    const else_ifs = try self.many(parseElseIf, .{});
    const else_branch = try self.maybe(parseElse, .{}) orelse okc.Stmt.Block.empty;
    return .{
        .location = location,
        .kind = .{ .iff = .{
            .branch = branch,
            .else_ifs = else_ifs,
            .else_block = else_branch,
        } },
    };
}

fn parseElseIf(self: *@This()) !okc.Stmt.Branch {
    try self.expect(.els, .quiet);
    try self.expect(.iff, .quiet);
    const branch = try self.parseBranch();
    return branch;
}

fn parseBranch(self: *@This()) !okc.Stmt.Branch {
    try self.expect(.parl, .loud);
    const condition = try self.parseExpr(.loud);
    try self.expect(.parr, .loud);
    const body = try self.parseBlock();
    return .{
        .condition = condition,
        .body = body,
    };
}

fn parseElse(self: *@This()) !okc.Stmt.Block {
    try self.expect(.els, .loud);
    const body = try self.parseBlock();
    return body;
}

fn parseAssignStmtPostfix(self: *@This()) !ExprStmtPostfix {
    const expr = try self.parseAssignPostfix();
    return .{ .assign = expr };
}

fn parseAssignPostfix(self: *@This()) !okc.Expr {
    try self.expect(.equ, .quiet);
    return self.parseExpr(.loud);
}

pub fn parseDeclareStmt(self: *@This()) !okc.Stmt {
    const declare = try self.parseDeclare();
    return .{
        .location = self.tmp_location,
        .kind = .{ .declare = declare },
    };
}

fn parseDeclare(self: *@This()) !okc.Stmt.Declare.Named {
    try self.expect(.let, .quiet);
    const mutable = try self.maybe(parseMutable, .{}) orelse false;
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    const typ = try self.maybe(parseTypAnnot, .{});
    try self.expect(.equ, .loud);
    const expr = try self.parseExpr(.loud);
    try self.expect(.semi, .loud);
    self.tmp_location = location;
    return .{
        .name = name,
        .bare = .{
            .typ = typ,
            .expr = expr,
            .mutable = mutable,
        },
    };
}

fn parseMutable(self: *@This()) Error!bool {
    try self.expect(.mut, .quiet);
    return true;
}

fn parseTypAnnot(self: *@This()) !okc.Typ {
    try self.expect(.colon, .loud);
    const typ = try self.parseTyp();
    return typ;
}

pub fn parseExprStmt(self: *@This()) !okc.Stmt {
    const expr = try self.parseExpr(.quiet);
    const postfix = try self.parseExprStmtPostfix();
    try self.expect(.semi, .loud);
    switch (postfix) {
        .none => return .{
            .location = expr.location,
            .kind = .{ .expr = .{ .expr = expr } },
        },
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

fn parseExprStmtPostfix(self: *@This()) !ExprStmtPostfix {
    return self.either(.{
        parseAssignStmtPostfix,
        parseOpAssignStmtPostfix,
    }) catch .none;
}

fn parseCallPostfix(self: *@This()) !Postfix {
    try self.expect(.parl, .quiet);
    const args = try self.sep(parseExpr, .{.loud});
    const location = self.getLocation();
    try self.expect(.parr, .loud);
    return .{
        .location = location,
        .kind = .{ .call = args },
    };
}

pub fn parseRetStmt(self: *@This()) !okc.Stmt {
    const location = self.getLocation();
    try self.expect(.ret, .quiet);
    const expr = try self.maybe(parseExpr, .{.loud});
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .{ .ret = .{
            .expr = expr,
        } },
    };
}

pub fn parseExpr(self: *@This(), mode: Mode) !okc.Expr {
    return self.parseExprPrior(0, mode);
}

fn parseExprPrior(self: *@This(), prior: u8, mode: Mode) Error!okc.Expr {
    var res = try self.parseExprPosted(mode);
    while (try self.parseBinPostfix(prior)) |bin_postfix| {
        const binary = try self.arena.create(okc.Expr.Binary);
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

fn parseBinPostfix(self: *@This(), prior: u8) !?BinPostfix {
    const cursor_before = self.cursor;
    const kind = self.parseBinOp(prior) orelse return null;
    const expr = self.parseExprPrior(kind.getPrior() + 1, .loud) catch |err| switch (err) {
        error.ParseFailed => {
            self.cursor = cursor_before;
            return null;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    return .{
        .kind = kind,
        .expr = expr,
    };
}

fn parseBinOp(self: *@This(), prior: u8) ?okc.Expr.Binary.Kind {
    const res = okc.Expr.Binary.Kind.fromLexeme(self.tokens[self.cursor].lexeme) orelse
        return null;
    if (res.getPrior() < prior) {
        return null;
    }
    self.cursor += 1;
    return res;
}

fn parseExprPosted(self: *@This(), mode: Mode) Error!okc.Expr {
    var res = try self.parseExprAtom(mode);
    while (try self.maybe(parsePostfix, .{})) |postfix| {
        switch (postfix.kind) {
            .method => |method_postfix| {
                const method = try self.arena.create(okc.Expr.Method);
                method.* = .{
                    .expr = res,
                    .vari = method_postfix.vari,
                    .args = method_postfix.args,
                    .name_location = method_postfix.name_location,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .method = method },
                };
            },
            .call => |args| {
                const call = try self.arena.create(okc.Expr.Call);
                call.* = .{
                    .expr = res,
                    .args = args,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .call = call },
                };
            },
            .field => |name| {
                const field = try self.arena.create(okc.Expr.Field);
                field.* = .{
                    .expr = res,
                    .vari = name,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .field = field },
                };
            },
            .elem => |index| {
                const elem = try self.arena.create(okc.Expr.Elem);
                elem.* = .{
                    .expr = res,
                    .index = index,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .elem = elem },
                };
            },
            .subslice => |subslice_postfix| {
                const subslice = try self.arena.create(okc.Expr.Subslice);
                subslice.* = .{
                    .expr = res,
                    .start = subslice_postfix.start,
                    .end = subslice_postfix.end,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .subslice = subslice },
                };
            },
        }
    }
    return res;
}

fn parsePostfix(self: *@This()) !Postfix {
    return self.either(.{
        parseMethodPostfix,
        parseCallPostfix,
        parseFieldPostfix,
        parseSubslicePostfix,
        parseElemPostfix,
    });
}

fn parseMethodPostfix(self: *@This()) !Postfix {
    try self.expect(.dot, .quiet);
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    const call_postfix = try self.parseCallPostfix();
    return .{
        .location = call_postfix.location,
        .kind = .{ .method = .{
            .vari = .{ .name = name },
            .args = call_postfix.kind.call,
            .name_location = location,
        } },
    };
}

fn parseSubslicePostfix(self: *@This()) !Postfix {
    try self.expect(.bral, .quiet);
    const start = try self.parseExpr(.quiet);
    try self.expect(.dot2, .quiet);
    const end = try self.parseExpr(.loud);
    const location = self.getLocation();
    try self.expect(.brar, .loud);
    return .{
        .location = location,
        .kind = .{ .subslice = .{
            .start = start,
            .end = end,
        } },
    };
}

fn parseElemPostfix(self: *@This()) !Postfix {
    try self.expect(.bral, .quiet);
    const index = try self.parseExpr(.loud);
    const location = self.getLocation();
    try self.expect(.brar, .loud);
    return .{
        .location = location,
        .kind = .{ .elem = index },
    };
}

fn parseFieldPostfix(self: *@This()) !Postfix {
    try self.expect(.dot, .quiet);
    const location = self.getLocation();
    const vari: okc.Expr.Var = try .parse(self, .loud);
    return .{
        .location = location,
        .kind = .{ .field = vari },
    };
}

pub fn getLocation(self: @This()) okc.Location {
    return self.tokens[self.cursor].location;
}

fn parseExprAtom(self: *@This(), mode: Mode) Error!okc.Expr {
    return self.either(.{
        parseAtExpr,
        parseParExpr,
        parseArrayExpr,
        parseUnaryExpr,
        parseInferStructExpr,
        parseStructExpr,
        parseIntExpr,
        parseStrExpr,
        parseCharExpr,
        parseVarExpr,
        parseUndefinedExpr,
        parseTrueExpr,
        parseFalseExpr,
    }) catch |err| {
        if (mode == .loud) {
            try self.fail("<expr>");
        }
        return err;
    };
}

fn parseAtExpr(self: *@This()) Error!okc.Expr {
    const start = self.getLocation();
    try self.expect(.att, .quiet);
    const name = try self.parseName(.loud);
    if (std.mem.eql(u8, name, "sizeof")) {
        try self.expect(.les, .loud);
        const typ = try self.parseTyp();
        const end = self.getLocation();
        try self.expect(.mor, .loud);
        return .{
            .location = start.combine(end),
            .kind = .{ .sizeof = typ },
        };
    }
    return error.ParseFailed;
}

fn parseArrayExpr(self: *@This()) Error!okc.Expr {
    const start = self.getLocation();
    const mtyp = try self.maybe(parseTypHint, .{});
    try self.expect(.bral, .quiet);
    const exprs = try self.sep(parseExpr, .{.loud});
    const end = self.getLocation();
    try self.expect(.brar, .loud);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .mtyp = mtyp,
            .typ = undefined,
        } },
    };
}

fn parseTypHint(self: *@This()) !okc.Typ {
    try self.expect(.les, .quiet);
    const typ = try self.parseTyp();
    try self.expect(.mor, .loud);
    return typ;
}

fn parseUnaryExpr(self: *@This()) Error!okc.Expr {
    const start = self.getLocation();
    const unary = try self.parseUnaryOp();
    const expr = try self.parseExprPosted(.loud);
    return .{
        .location = start.combine(expr.location),
        .kind = try .makeUnary(unary, expr, self.arena),
    };
}

fn parseUnaryOp(self: *@This()) !okc.Expr.Unary {
    self.cursor += 1;
    return okc.Expr.Unary.fromLexeme(self.tokens[self.cursor - 1].lexeme) orelse error.ParseFailed;
}

fn parseInferStructExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    try self.expect(.dot, .quiet);
    const fields = try self.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .struc = .{ .fields = fields } },
    };
}

fn parseParExpr(self: *@This()) Error!okc.Expr {
    const start = self.getLocation();
    try self.expect(.parl, .quiet);
    var expr = try self.parseExpr(.loud);
    const end = self.getLocation();
    try self.expect(.parr, .loud);
    expr.location = start.combine(end);
    return expr;
}

fn parseStructExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    const fields = try self.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .named_struc = .{
            .name = name,
            .bare = .{ .fields = fields },
        } },
    };
}

fn parseStructExprBody(self: *@This()) ![]okc.Expr.Struct.Field {
    try self.expect(.curl, .quiet);
    const fields = try self.sep(parseNewField, .{});
    try self.expect(.curr, .loud);
    return fields;
}

fn parseNewField(self: *@This()) !okc.Expr.Struct.Field {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.equ, .loud);
    const expr = try self.parseExpr(.loud);
    return .{
        .name = name,
        .expr = expr,
        .location = location,
    };
}

fn parseVarExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    const vari: okc.Expr.Var = try .parse(self, .quiet);
    return .{
        .location = location,
        .kind = .{ .vari = vari },
    };
}

fn parseStrExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    const str = try self.parseStr();
    return .{
        .location = location,
        .kind = .{ .str = .{ .bare = str } },
    };
}

fn parseUndefinedExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    try self.expect(.undef, .quiet);
    return .{
        .location = location,
        .kind = .{ .undef = .{} },
    };
}

fn parseTrueExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    try self.expect(.tru, .quiet);
    return .{
        .location = location,
        .kind = .{ .bool = true },
    };
}

fn parseFalseExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    try self.expect(.fals, .quiet);
    return .{
        .location = location,
        .kind = .{ .bool = false },
    };
}

fn parseCharExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    const char = try self.parseChar();
    return .{
        .location = location,
        .kind = .{ .char = char },
    };
}

fn parseIntExpr(self: *@This()) Error!okc.Expr {
    const location = self.getLocation();
    const val = try self.parseInt();
    return .{
        .location = location,
        .kind = .{ .int = .{ .val = val } },
    };
}

pub fn parseName(self: *@This(), mode: Mode) ![]const u8 {
    return try self.maybe(parseLexeme, .{.name}) orelse {
        if (mode == .loud) {
            try self.fail("<name>");
        }
        return error.ParseFailed;
    };
}

fn parseInt(self: *@This()) !u64 {
    return self.parseLexeme(.int);
}

fn parseChar(self: *@This()) !u8 {
    return self.parseLexeme(.char);
}

fn parseStr(self: *@This()) ![]const u8 {
    return self.parseLexeme(.str);
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

fn deinit(self: *@This()) void {
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

const ExprStmtPostfix = union(enum) {
    assign: okc.Expr,
    none,
    op_assign: OpAssignPostfix,
};

const OpAssignPostfix = struct {
    kind: okc.Expr.Binary.Kind,
    expr: okc.Expr,
};

const BinPostfix = struct {
    kind: okc.Expr.Binary.Kind,
    expr: okc.Expr,
};

const Postfix = struct {
    kind: Kind,
    location: okc.Location,

    const Kind = union(enum) {
        call: []okc.Expr,
        elem: okc.Expr,
        field: okc.Expr.Var,
        method: Method,
        subslice: Subslice,
    };

    const Method = struct {
        vari: okc.Expr.Var,
        args: []okc.Expr,
        name_location: okc.Location,
    };

    const Subslice = struct {
        start: okc.Expr,
        end: okc.Expr,
    };
};

const ErrMsgsPrinter = struct {
    msgs: []const []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.msgs.len == 1) {
            try writer.print("     expected  {s}", .{self.msgs[0]});
            return;
        }
        try writer.writeAll("     expected:");
        for (self.msgs) |msg| {
            try writer.print("\n       - {s}", .{msg});
        }
    }
};

pub const Mode = enum {
    loud,
    quiet,
};
