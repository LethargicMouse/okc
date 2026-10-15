const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const Item = @import("Item.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;
const Location = @import("Location.zig");
const Module = @import("Module.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/mod.zig").Typ;

gpa: std.mem.Allocator,
tokens: []const Lexer.Token,
err_msgs: ErrMsgs = .empty,
tmp_name: []const u8 = "<unknown>",
tmp_location: Location = .fake,
cursor: usize = 0,
err_cursor: usize = 0,

pub fn init(
    gpa: std.mem.Allocator,
    tokens: []const Lexer.Token,
) @This() {
    return .{
        .gpa = gpa,
        .tokens = tokens,
    };
}

pub fn run(self: *@This()) error{ OutOfMemory, Handled }!Module {
    defer self.deinit();
    const module = try self.maybe(parseModule, .{}) orelse {
        std.log.err("failed to parse {f}\n{f}\n        found  {s}", .{
            self.tokens[self.err_cursor].location,
            self.err_msgs,
            Lexeme.describe(self.tokens[self.err_cursor].lexeme),
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

fn parseModule(self: *@This()) !Module {
    const items = try self.many(parseItem, .{});
    const location = self.getLocation();
    try self.expect(.eof, .quiet);
    return .{
        .items = items,
        .location = location,
    };
}

fn parseItem(self: *@This()) Error!Item {
    return self.either(.{
        parseFunItem,
        parseStructItem,
        parseExtFunItem,
        parseConstantItem,
        parseTypAliasItem,
        parseUseItem,
    }) catch |err| {
        try self.fail("<item>");
        return err;
    };
}

fn parseUseItem(self: *@This()) !Item {
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

fn parseTypAliasItem(self: *@This()) !Item {
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

fn parseConstantItem(self: *@This()) !Item {
    const named = try self.parseDeclare();
    return .{
        .name = named.name,
        .location = self.tmp_location,
        .kind = .{ .constant = named.declare },
    };
}

fn parseExtFunItem(self: *@This()) !Item {
    const ext_fun = try self.parseExtFun();
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .ext_fun = ext_fun },
    };
}

fn parseFunItem(self: *@This()) !Item {
    const fun = try self.parseFun();
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .fun = fun },
    };
}

fn parseStructItem(self: *@This()) !Item {
    const struc = try self.parseStruct();
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .struc = struc },
    };
}

fn parseStruct(self: *@This()) !Item.Struct {
    try self.expect(.struc, .quiet);
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    const generics = try self.maybe(parseGenerics, .{}) orelse &.{};
    try self.expect(.curl, .loud);
    const fields = try self.sep(parseFieldDecl, .{});
    try self.expect(.curr, .quiet);
    self.tmp_location = location;
    self.tmp_name = name;
    return .{
        .generics = generics,
        .fields = fields,
    };
}

fn parseGenerics(self: *@This()) ![]const Item.Generic {
    try self.expect(.les, .quiet);
    const res = try self.sep(parseGeneric, .{});
    try self.expect(.mor, .quiet);
    return res;
}

fn parseGeneric(self: *@This()) !Item.Generic {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    return .{
        .name = name,
        .location = location,
    };
}

fn parseFieldDecl(self: *@This()) !Item.Struct.Field {
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

fn parseExtFun(self: *@This()) !Item.Fun.Extern {
    try self.expect(.ext, .quiet);
    const header = try self.parseHeader(.loud);
    try self.expect(.semi, .loud);
    return .{
        .header = header,
    };
}

fn parseHeader(self: *@This(), mode: ParseMode) !Item.Fun.Header {
    try self.expect(.fun, mode);
    self.tmp_location = self.getLocation();
    self.tmp_name = try self.parseName(.loud);
    const generics = try self.maybe(parseGenerics, .{}) orelse &.{};
    try self.expect(.parl, .loud);
    const params = try self.sep(parseParam, .{});
    try self.expect(.parr, .quiet);
    const ret_typ = try self.parseTyp();
    return .{
        .generics = generics,
        .params = params,
        .ret_typ = ret_typ,
    };
}

fn sep(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    if (try self.maybe(parse, args)) |first| {
        try vec.append(self.gpa, first);
        while (true) {
            try self.maybe(expect, .{ .comma, .loud }) orelse break;
            if (try self.maybe(parse, args)) |item| {
                try vec.append(self.gpa, item);
            } else break;
        }
    }
    const slice = try Module.arena.alloc(ParseRes(parse, args), vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseParam(self: *@This()) !Item.Fun.Header.Param {
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

fn parseTyp(self: *@This()) Error!Typ {
    return self.either(.{
        parseFunTyp,
        parseGenericTyp,
        parseVerbalTyp,
        parseMutPtrTyp,
        parsePtrTyp,
        parseArrayTyp,
        parseSliceTyp,
    }) catch |err| {
        try self.fail("<type>");
        return err;
    };
}

fn parseFunTyp(self: *@This()) Error!Typ {
    try self.expect(.fun, .quiet);
    try self.expect(.parl, .loud);
    const params = try self.sep(parseTyp, .{});
    try self.expect(.parr, .quiet);
    const ret_typ = try self.parseTyp();
    const ptr = try Typ.memo.box(ret_typ);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

fn parseSliceTyp(self: *@This()) !Typ {
    try self.expect(.bral, .quiet);
    try self.expect(.brar, .loud);
    var mutable = true;
    try self.maybe(expect, .{ .mut, .quiet }) orelse {
        mutable = false;
    };
    const typ = try self.parseTyp();
    const ptr = try Typ.memo.box(typ);
    return .{ .slice = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

fn parseGenericTyp(self: *@This()) Error!Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    try self.expect(.les, .quiet);
    const generics = try self.sep(parseTyp, .{});
    try self.expect(.mor, .quiet);
    return .{ .loc_name = .{
        .bare = .{
            .name = name,
            .generics = generics,
        },
        .location = location,
    } };
}

fn parseArrayTyp(self: *@This()) !Typ {
    try self.expect(.bral, .quiet);
    const len = try self.parseInt();
    try self.expect(.brar, .loud);
    const typ = try self.parseTyp();
    const ptr = try Typ.memo.box(typ);
    return .{ .array = .{
        .len = len,
        .typ = ptr,
    } };
}

fn either(self: *@This(), comptime parses: anytype) !ParseRes(parses[0], .{}) {
    inline for (parses) |parse| {
        if (try self.maybe(parse, .{})) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

fn parseMutPtrTyp(self: *@This()) Error!Typ {
    try self.expect(.amp, .quiet);
    try self.expect(.mut, .quiet);
    const typ = try self.parseTyp();
    const ptr = try Typ.memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = true,
    } };
}

fn parsePtrTyp(self: *@This()) Error!Typ {
    try self.expect(.amp, .quiet);
    const typ = try self.parseTyp();
    const ptr = try Typ.memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = false,
    } };
}

fn parseVerbalTyp(self: *@This()) Error!Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    return Typ.fromName(name, location);
}

fn many(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    while (try self.maybe(parse, args)) |item| {
        try vec.append(self.gpa, item);
    }
    const slice = try Module.arena.alloc(ParseRes(parse, args), vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn ParseRes(fun: anytype, args: anytype) type {
    return @typeInfo(@TypeOf(@call(.auto, fun, .{@as(*@This(), undefined)} ++ args)))
        .error_union.payload;
}

fn maybe(self: *@This(), parse: anytype, args: anytype) !?ParseRes(parse, args) {
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

fn parseFun(self: *@This()) !Item.Fun {
    const header = try self.parseHeader(.quiet);
    const location = self.tmp_location;
    const name = self.tmp_name;
    const block = try self.parseBlock();
    self.tmp_location = location;
    self.tmp_name = name;
    return .{
        .header = header,
        .body = block,
    };
}

fn parseBlock(self: *@This()) Error![]Stmt {
    try self.expect(.curl, .loud);
    const stmts = try self.many(parseStmt, .{});
    try self.expect(.curr, .quiet);
    return stmts;
}

fn parseStmt(self: *@This()) !Stmt {
    return self.either(.{
        parseUnreachableStmt,
        parseBreakStmt,
        parseRetStmt,
        parseDeclareStmt,
        parseIfStmt,
        parseForStmt,
        parseWhileStmt,
        parseIgnoreStmt,
        parseExprStmt,
    }) catch |err| {
        try self.fail("<Stmt>");
        return err;
    };
}

fn parseUnreachableStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.unre, .quiet);
    try self.expect(.semi, .loud);
    return .{
        .location = location,
        .kind = .unre,
    };
}

fn parseBreakStmt(self: *@This()) !Stmt {
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

fn parseOpAssignBinOp(self: *@This()) !Expr.Binary.Kind {
    const res = Expr.Binary.Kind.fromLexeme(self.tokens[self.cursor].lexeme) orelse
        return error.ParseFailed;
    if (res.getClass() != .arith) {
        return error.ParseFailed;
    }
    self.cursor += 1;
    return res;
}

fn parseIgnoreStmt(self: *@This()) !Stmt {
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

fn parseForStmt(self: *@This()) !Stmt {
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

fn parseRangeEnd(self: *@This()) !Expr {
    try self.expect(.dot2, .quiet);
    return self.parseExpr(.loud);
}

fn parseWhileStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.whi, .quiet);
    const branch = try self.parseBranch();
    return .{ .location = location, .kind = .{ .whi = .{ .branch = branch } } };
}

fn parseIfStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.iff, .quiet);
    const branch = try self.parseBranch();
    const else_ifs = try self.many(parseElseIf, .{});
    const else_branch = try self.maybe(parseElse, .{}) orelse @constCast(&.{});
    return .{
        .location = location,
        .kind = .{ .iff = .{
            .branch = branch,
            .else_ifs = else_ifs,
            .else_branch = else_branch,
        } },
    };
}

fn parseElseIf(self: *@This()) !Stmt.Branch {
    try self.expect(.els, .quiet);
    try self.expect(.iff, .quiet);
    const branch = try self.parseBranch();
    return branch;
}

fn parseBranch(self: *@This()) !Stmt.Branch {
    try self.expect(.parl, .loud);
    const condition = try self.parseExpr(.loud);
    try self.expect(.parr, .loud);
    const body = try self.parseBlock();
    return .{
        .condition = condition,
        .body = body,
    };
}

fn parseElse(self: *@This()) ![]Stmt {
    try self.expect(.els, .loud);
    const body = try self.parseBlock();
    return body;
}

fn parseAssignStmtPostfix(self: *@This()) !ExprStmtPostfix {
    const expr = try self.parseAssignPostfix();
    return .{ .assign = expr };
}

fn parseAssignPostfix(self: *@This()) !Expr {
    try self.expect(.equ, .quiet);
    return self.parseExpr(.loud);
}

fn parseDeclareStmt(self: *@This()) !Stmt {
    const declare = try self.parseDeclare();
    return .{
        .location = self.tmp_location,
        .kind = .{ .declare = declare },
    };
}

fn parseDeclare(self: *@This()) !Item.Declare.Named {
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
        .declare = .{
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

fn parseTypAnnot(self: *@This()) !Typ {
    try self.expect(.colon, .loud);
    const typ = try self.parseTyp();
    return typ;
}

fn parseExprStmt(self: *@This()) !Stmt {
    const expr = try self.parseExpr(.quiet);
    const postfix = try self.parseExprStmtPostfix();
    try self.expect(.semi, .loud);
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
    try self.expect(.parr, .quiet);
    return .{
        .location = location,
        .kind = .{ .call = args },
    };
}

fn parseRetStmt(self: *@This()) !Stmt {
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

fn parseExpr(self: *@This(), mode: ParseMode) !Expr {
    return self.parseExprPrior(0, mode);
}

fn parseExprPrior(self: *@This(), prior: u8, mode: ParseMode) Error!Expr {
    var res = try self.parseExprPosted(mode);
    while (try self.parseBinPostfix(prior)) |bin_postfix| {
        const binary = try Module.arena.create(Expr.Binary);
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

fn parseBinOp(self: *@This(), prior: u8) ?Expr.Binary.Kind {
    const res = Expr.Binary.Kind.fromLexeme(self.tokens[self.cursor].lexeme) orelse
        return null;
    if (res.getPrior() < prior) {
        return null;
    }
    self.cursor += 1;
    return res;
}

fn parseExprPosted(self: *@This(), mode: ParseMode) Error!Expr {
    var res = try self.parseExprAtom(mode);
    while (try self.maybe(parsePostfix, .{})) |postfix| {
        switch (postfix.kind) {
            .method => |method_postfix| {
                const method = try Module.arena.create(Expr.Method);
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
                const call = try Module.arena.create(Expr.Call);
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
                const field = try Module.arena.create(Expr.Field);
                field.* = .{
                    .expr = res,
                    .name = name,
                };
                res = .{
                    .location = res.location.combine(postfix.location),
                    .kind = .{ .field = field },
                };
            },
            .elem => |index| {
                const elem = try Module.arena.create(Expr.Elem);
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
                const subslice = try Module.arena.create(Expr.Subslice);
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
    const name = try self.parseName(.loud);
    return .{
        .location = location,
        .kind = .{ .field = name },
    };
}

fn getLocation(self: @This()) Location {
    return self.tokens[self.cursor].location;
}

fn parseExprAtom(self: *@This(), mode: ParseMode) Error!Expr {
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

fn parseAtExpr(self: *@This()) Error!Expr {
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

fn parseArrayExpr(self: *@This()) Error!Expr {
    const start = self.getLocation();
    const mtyp = try self.maybe(parseTypHint, .{});
    try self.expect(.bral, .quiet);
    const exprs = try self.sep(parseExpr, .{.loud});
    const end = self.getLocation();
    try self.expect(.brar, .quiet);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .mtyp = mtyp,
            .typ = undefined,
        } },
    };
}

fn parseTypHint(self: *@This()) !Typ {
    try self.expect(.les, .quiet);
    const typ = try self.parseTyp();
    try self.expect(.mor, .loud);
    return typ;
}

fn parseUnaryExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const kind = try self.parseUnaryOp();
    const expr = try self.parseExprPosted(.loud);
    const unary = try Module.arena.create(Expr.Unary);
    unary.* = .{
        .kind = kind,
        .expr = expr,
    };
    return .{
        .location = location.combine(expr.location),
        .kind = .{ .unary = unary },
    };
}

fn parseUnaryOp(self: *@This()) !Expr.Unary.Kind {
    const res = Expr.Unary.Kind.fromLexeme(self.tokens[self.cursor].lexeme) orelse
        return error.ParseFailed;
    self.cursor += 1;
    return res;
}

fn parseInferStructExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.dot, .quiet);
    const fields = try self.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .struc = .{ .fields = fields } },
    };
}

fn parseParExpr(self: *@This()) Error!Expr {
    const start = self.getLocation();
    try self.expect(.parl, .quiet);
    var expr = try self.parseExpr(.loud);
    const end = self.getLocation();
    try self.expect(.parr, .loud);
    expr.location = start.combine(end);
    return expr;
}

fn parseStructExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    const fields = try self.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .named_struc = .{
            .name = name,
            .struc = .{ .fields = fields },
        } },
    };
}

fn parseStructExprBody(self: *@This()) ![]Expr.Struct.Field {
    try self.expect(.curl, .quiet);
    const fields = try self.sep(parseNewField, .{});
    try self.expect(.curr, .quiet);
    return fields;
}

fn parseNewField(self: *@This()) !Expr.Struct.Field {
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

fn parseVarExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    return .{
        .location = location,
        .kind = .{ .vari = .{ .name = name } },
    };
}

fn parseStrExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const str = try self.parseStr();
    return .{
        .location = location,
        .kind = .{ .str = str },
    };
}

fn parseUndefinedExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.undef, .quiet);
    return .{
        .location = location,
        .kind = .{ .undef = .{} },
    };
}

fn parseTrueExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.tru, .quiet);
    return .{
        .location = location,
        .kind = .{ .bool = true },
    };
}

fn parseFalseExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.fals, .quiet);
    return .{
        .location = location,
        .kind = .{ .bool = false },
    };
}

fn parseCharExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const char = try self.parseChar();
    return .{
        .location = location,
        .kind = .{ .char = char },
    };
}

fn parseIntExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const val = try self.parseInt();
    return .{
        .location = location,
        .kind = .{ .int = .{ .val = val } },
    };
}

fn parseName(self: *@This(), mode: ParseMode) ![]const u8 {
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
    comptime tag: @typeInfo(Lexeme).@"union".tag_type.?,
) Error!@typeInfo(Lexeme).@"union".field_types[@backingInt(tag)] {
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

fn expect(self: *@This(), lexeme: @typeInfo(Lexeme).@"union".tag_type.?, mode: ParseMode) !void {
    if (self.tokens[self.cursor].lexeme == lexeme) {
        self.cursor += 1;
    } else {
        if (mode == .loud) {
            try self.fail(Lexeme.describe(lexeme));
        }
        return error.ParseFailed;
    }
}

fn fail(self: *@This(), msg: []const u8) !void {
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
    assign: Expr,
    none,
    op_assign: OpAssignPostfix,
};

const OpAssignPostfix = struct {
    kind: Expr.Binary.Kind,
    expr: Expr,
};

const BinPostfix = struct {
    kind: Expr.Binary.Kind,
    expr: Expr,
};

const Postfix = struct {
    kind: Kind,
    location: Location,

    const Kind = union(enum) {
        call: []Expr,
        elem: Expr,
        field: []const u8,
        method: Method,
        subslice: Subslice,
    };

    const Method = struct {
        vari: Expr.Var,
        args: []Expr,
        name_location: Location,
    };

    const Subslice = struct {
        start: Expr,
        end: Expr,
    };
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

const ParseMode = enum {
    loud,
    quiet,
};
