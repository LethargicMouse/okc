const std = @import("std");

const ast = @import("ast/mod.zig");
const Expr = @import("Expr/Expr.zig");
const Item = @import("Item.zig");
const Lexer = @import("Lexer.zig");
const Lexeme = Lexer.Lexeme;
const Location = @import("Location.zig");
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

pub fn run(self: *@This()) error{ OutOfMemory, Handled }!ast.Module {
    defer self.deinit();
    const module = try self.maybe(ast.Module, parseModule, .{}) orelse {
        std.log.err("failed to parse {f}\n{f}\n        found  {s}", .{
            self.tokens[self.err_cursor].location,
            self.err_msgs,
            self.tokens[self.err_cursor].lexeme.describe(),
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

fn parseModule(self: *@This()) !ast.Module {
    const items = try self.many(Item, parseItemLoud, .{});
    const location = self.getLocation();
    try self.expect(.eof);
    return .{
        .items = items,
        .location = location,
    };
}

fn parseItemLoud(self: *@This()) Error!Item {
    return self.either(Item, &.{
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
    try self.expect(.use);
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    try self.expectLoud(.semi);
    return .{
        .location = location,
        .name = name,
        .kind = .use,
    };
}

fn parseTypAliasItem(self: *@This()) !Item {
    try self.expect(.typ);
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    try self.expectLoud(.equ);
    const typ = try self.parseTypLoud();
    try self.expectLoud(.semi);
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
    try self.expect(.struc);
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    const generics = try self.maybe([]const Item.Generic, parseGenerics, .{}) orelse &.{};
    try self.expectLoud(.curl);
    const fields = try self.parseSep(Item.Struct.Field, parseFieldDeclLoud);
    try self.expect(.curr);
    self.tmp_location = location;
    self.tmp_name = name;
    return .{
        .generics = generics,
        .fields = fields,
    };
}

fn parseGenerics(self: *@This()) ![]const Item.Generic {
    try self.expect(.les);
    const res = try self.parseSep(Item.Generic, parseGenericLoud);
    try self.expect(.mor);
    return res;
}

fn parseGenericLoud(self: *@This()) !Item.Generic {
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    return .{
        .name = name,
        .location = location,
    };
}

fn parseFieldDeclLoud(self: *@This()) !Item.Struct.Field {
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    try self.expectLoud(.colon);
    const typ = try self.parseTypLoud();
    const default = try self.maybe(Expr, parseAssignPostfix, .{});
    return .{
        .name = name,
        .typ = typ,
        .location = location,
        .default = default,
    };
}

fn parseExtFun(self: *@This()) !Item.Fun.Extern {
    try self.expect(.ext);
    const header = try self.parseHeaderLoud();
    try self.expectLoud(.semi);
    return .{
        .header = header,
    };
}

fn parseHeaderLoud(self: *@This()) !Item.Fun.Header {
    const header = try self.maybe(Item.Fun.Header, parseHeader, .{});
    return header orelse {
        try self.fail("`fn`");
        return error.ParseFailed;
    };
}

fn parseHeader(self: *@This()) !Item.Fun.Header {
    try self.expect(.fun);
    self.tmp_location = self.getLocation();
    self.tmp_name = try self.parseNameLoud();
    const generics = try self.maybe([]const Item.Generic, parseGenerics, .{}) orelse &.{};
    try self.expectLoud(.parl);
    const params = try self.parseSep(Item.Fun.Header.Param, parseParamLoud);
    try self.expect(.parr);
    const ret_typ = try self.parseTypLoud();
    return .{
        .generics = generics,
        .params = params,
        .ret_typ = ret_typ,
    };
}

fn parseSep(self: *@This(), T: type, parse: fn (*@This()) Error!T) ![]T {
    var vec = std.ArrayList(T).empty;
    defer vec.deinit(self.gpa);
    if (try self.maybe(T, parse, .{})) |first| {
        try vec.append(self.gpa, first);
        while (true) {
            self.expectLoud(.comma) catch |err| switch (err) {
                error.ParseFailed => break,
                error.OutOfMemory => return error.OutOfMemory,
            };
            if (try self.maybe(T, parse, .{})) |item| {
                try vec.append(self.gpa, item);
            } else break;
        }
    }
    const slice = try ast.arena.allocator().alloc(T, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn parseParamLoud(self: *@This()) !Item.Fun.Header.Param {
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    try self.expectLoud(.colon);
    const typ = try self.parseTypLoud();
    return .{
        .name = name,
        .typ = typ,
        .location = location,
    };
}

fn parseTypLoud(self: *@This()) Error!Typ {
    return self.either(Typ, .{
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
    try self.expect(.fun);
    try self.expectLoud(.parl);
    const params = try self.parseSep(Typ, parseTypLoud);
    try self.expect(.parr);
    const ret_typ = try self.parseTypLoud();
    const ptr = try Typ.memo.box(ret_typ);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

fn parseSliceTyp(self: *@This()) !Typ {
    try self.expect(.bral);
    try self.expectLoud(.brar);
    var mutable = true;
    self.expect(.mut) catch |err| switch (err) {
        error.ParseFailed => mutable = false,
    };
    const typ = try self.parseTypLoud();
    const ptr = try Typ.memo.box(typ);
    return .{ .slice = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

fn parseGenericTyp(self: *@This()) Error!Typ {
    const location = self.getLocation();
    const name = try self.parseName();
    try self.expect(.les);
    const generics = try self.parseSep(Typ, parseTypLoud);
    try self.expect(.mor);
    return .{ .loc_name = .{
        .bare = .{
            .name = name,
            .generics = generics,
        },
        .location = location,
    } };
}

fn parseArrayTyp(self: *@This()) !Typ {
    try self.expect(.bral);
    const len = try self.parseInt();
    try self.expectLoud(.brar);
    const typ = try self.parseTypLoud();
    const ptr = try Typ.memo.box(typ);
    return .{ .array = .{
        .len = len,
        .typ = ptr,
    } };
}

fn either(self: *@This(), T: type, comptime parses: anytype) !T {
    inline for (parses) |parse| {
        if (try self.maybe(T, parse, .{})) |res| {
            return res;
        }
    }
    return error.ParseFailed;
}

fn parseMutPtrTyp(self: *@This()) Error!Typ {
    try self.expect(.amp);
    try self.expect(.mut);
    const typ = try self.parseTypLoud();
    const ptr = try Typ.memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = true,
    } };
}

fn parsePtrTyp(self: *@This()) Error!Typ {
    try self.expect(.amp);
    const typ = try self.parseTypLoud();
    const ptr = try Typ.memo.box(typ);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = false,
    } };
}

fn parseVerbalTyp(self: *@This()) Error!Typ {
    const location = self.getLocation();
    const name = try self.parseName();
    return Typ.fromName(name, location);
}

fn many(self: *@This(), T: type, parse: anytype, args: anytype) ![]T {
    var vec = std.ArrayList(T).empty;
    defer vec.deinit(self.gpa);
    while (try self.maybe(T, parse, args)) |item| {
        try vec.append(self.gpa, item);
    }
    const slice = try ast.arena.allocator().alloc(T, vec.items.len);
    @memcpy(slice, vec.items);
    return slice;
}

fn maybe(self: *@This(), T: type, parse: anytype, args: anytype) !?T {
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
    const header = try self.parseHeader();
    const location = self.tmp_location;
    const name = self.tmp_name;
    const block = try self.parseBlockLoud();
    self.tmp_location = location;
    self.tmp_name = name;
    return .{
        .header = header,
        .body = block,
    };
}

fn parseBlockLoud(self: *@This()) Error![]Stmt {
    try self.expectLoud(.curl);
    const stmts = try self.many(Stmt, parseStmtLoud, .{});
    try self.expect(.curr);
    return stmts;
}

fn parseStmtLoud(self: *@This()) !Stmt {
    return self.either(Stmt, .{
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
    try self.expect(.unre);
    try self.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .unre,
    };
}

fn parseBreakStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.brek);
    try self.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .brek,
    };
}

fn parseOpAssignStmtPostfix(
    self: *@This(),
) !ExprStmtPostfix {
    const kind = try self.parseOpAssignBinOp();
    try self.expect(.equ);
    const expr = try self.parseExprLoud();
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
    try self.expect(.wild);
    try self.expectLoud(.equ);
    const expr = try self.parseExprLoud();
    try self.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .{ .ignore = .{
            .expr = expr,
        } },
    };
}

fn parseForStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.whi);
    try self.expectLoud(.parl);
    const vari_location = self.getLocation();
    const vari = try self.parseNameLoud();
    try self.expectLoud(.colon);
    const expr = try self.parseExprLoud();
    const mend = try self.maybe(Expr, parseRangeEnd, .{});
    try self.expectLoud(.parr);
    const body = try self.parseBlockLoud();
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
    try self.expect(.dot2);
    return self.parseExprLoud();
}

fn parseWhileStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.whi);
    const branch = try self.parseBranch();
    return .{ .location = location, .kind = .{ .whi = .{ .branch = branch } } };
}

fn parseIfStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.iff);
    const branch = try self.parseBranch();
    const else_ifs = try self.many(Stmt.Branch, parseElseIf, .{});
    const else_branch = try self.maybe([]Stmt, parseElseLoud, .{}) orelse @constCast(&.{});
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
    try self.expect(.els);
    try self.expect(.iff);
    const branch = try self.parseBranch();
    return branch;
}

fn parseBranch(self: *@This()) !Stmt.Branch {
    try self.expectLoud(.parl);
    const condition = try self.parseExprLoud();
    try self.expectLoud(.parr);
    const body = try self.parseBlockLoud();
    return .{
        .condition = condition,
        .body = body,
    };
}

fn parseElseLoud(self: *@This()) ![]Stmt {
    try self.expectLoud(.els);
    const body = try self.parseBlockLoud();
    return body;
}

fn parseAssignStmtPostfix(self: *@This()) !ExprStmtPostfix {
    const expr = try self.parseAssignPostfix();
    return .{ .assign = expr };
}

fn parseAssignPostfix(self: *@This()) !Expr {
    try self.expect(.equ);
    return self.parseExprLoud();
}

fn parseDeclareStmt(self: *@This()) !Stmt {
    const declare = try self.parseDeclare();
    return .{
        .location = self.tmp_location,
        .kind = .{ .declare = declare },
    };
}

fn parseDeclare(self: *@This()) !Stmt.Declare.Named {
    try self.expect(.let);
    const mutable = try self.maybe(bool, parseMutable, .{}) orelse false;
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    const typ = try self.maybe(Typ, parseTypAnnotLoud, .{});
    try self.expectLoud(.equ);
    const expr = try self.parseExprLoud();
    try self.expectLoud(.semi);
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
    try self.expect(.mut);
    return true;
}

fn parseTypAnnotLoud(self: *@This()) !Typ {
    try self.expectLoud(.colon);
    const typ = try self.parseTypLoud();
    return typ;
}

fn parseExprStmt(self: *@This()) !Stmt {
    const expr = try self.parseExpr();
    const postfix = try self.parseExprStmtPostfix();
    try self.expectLoud(.semi);
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
    return self.either(ExprStmtPostfix, &.{
        parseAssignStmtPostfix,
        parseOpAssignStmtPostfix,
    }) catch .none;
}

fn parseCallPostfix(self: *@This()) !Postfix {
    try self.expect(.parl);
    const args = try self.parseSep(Expr, parseExprLoud);
    const location = self.getLocation();
    try self.expect(.parr);
    return .{
        .location = location,
        .kind = .{ .call = args },
    };
}

fn parseRetStmt(self: *@This()) !Stmt {
    const location = self.getLocation();
    try self.expect(.ret);
    const expr = try self.maybe(Expr, parseExprLoud, .{});
    try self.expectLoud(.semi);
    return .{
        .location = location,
        .kind = .{ .ret = .{
            .expr = expr,
        } },
    };
}

fn parseExprLoud(self: *@This()) !Expr {
    const expr = try self.maybe(Expr, parseExpr, .{});
    return expr orelse {
        try self.fail("<expr>");
        return error.ParseFailed;
    };
}

fn parseExpr(self: *@This()) !Expr {
    return self.parseExprPrior(0, .quiet);
}

fn parseExprPrior(self: *@This(), prior: u8, mode: ParseMode) Error!Expr {
    var res = try self.parseExprPosted(mode);
    while (try self.parseBinPostfix(prior)) |bin_postfix| {
        const binary = try ast.arena.allocator().create(Expr.Binary);
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

fn parseExprPostedLoud(self: *@This()) Error!Expr {
    return self.parseExprPosted(.loud);
}

fn parseExprPosted(self: *@This(), mode: ParseMode) Error!Expr {
    var res = try self.parseExprAtom(mode);
    while (try self.maybe(Postfix, parsePostfix, .{})) |postfix| {
        switch (postfix.kind) {
            .method => |method_postfix| {
                const method = try ast.arena.allocator().create(Expr.Method);
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
                const call = try ast.arena.allocator().create(Expr.Call);
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
                const field = try ast.arena.allocator().create(Expr.Field);
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
                const elem = try ast.arena.allocator().create(Expr.Elem);
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
                const subslice = try ast.arena.allocator().create(Expr.Subslice);
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
    return self.either(Postfix, .{
        parseMethodPostfix,
        parseCallPostfix,
        parseFieldPostfix,
        parseSubslicePostfix,
        parseElemPostfix,
    });
}

fn parseMethodPostfix(self: *@This()) !Postfix {
    try self.expect(.dot);
    const location = self.getLocation();
    const name = try self.parseName();
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
    try self.expect(.bral);
    const start = try self.parseExpr();
    try self.expect(.dot2);
    const end = try self.parseExprLoud();
    const location = self.getLocation();
    try self.expectLoud(.brar);
    return .{
        .location = location,
        .kind = .{ .subslice = .{
            .start = start,
            .end = end,
        } },
    };
}

fn parseElemPostfix(self: *@This()) !Postfix {
    try self.expect(.bral);
    const index = try self.parseExprLoud();
    const location = self.getLocation();
    try self.expectLoud(.brar);
    return .{
        .location = location,
        .kind = .{ .elem = index },
    };
}

fn parseFieldPostfix(self: *@This()) !Postfix {
    try self.expect(.dot);
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    return .{
        .location = location,
        .kind = .{ .field = name },
    };
}

fn getLocation(self: @This()) Location {
    return self.tokens[self.cursor].location;
}

fn parseExprAtom(self: *@This(), mode: ParseMode) Error!Expr {
    return self.either(Expr, .{
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
    try self.expect(.att);
    const name = try self.parseNameLoud();
    if (std.mem.eql(u8, name, "sizeof")) {
        try self.expectLoud(.les);
        const typ = try self.parseTypLoud();
        const end = self.getLocation();
        try self.expectLoud(.mor);
        return .{
            .location = start.combine(end),
            .kind = .{ .sizeof = typ },
        };
    }
    return error.ParseFailed;
}

fn parseArrayExpr(self: *@This()) Error!Expr {
    const start = self.getLocation();
    const mtyp = try self.maybe(Typ, parseTypHint, .{});
    try self.expect(.bral);
    const exprs = try self.parseSep(Expr, parseExprLoud);
    const end = self.getLocation();
    try self.expect(.brar);
    return .{
        .location = start.combine(end),
        .kind = .{ .array = .{
            .exprs = exprs,
            .mtyp = mtyp,
        } },
    };
}

fn parseTypHint(self: *@This()) !Typ {
    try self.expect(.les);
    const typ = try self.parseTypLoud();
    try self.expectLoud(.mor);
    return typ;
}

fn parseUnaryExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const kind = try self.parseUnaryOp();
    const expr = try self.parseExprPostedLoud();
    const unary = try ast.arena.allocator().create(Expr.Unary);
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
    try self.expect(.dot);
    const fields = try self.parseStructExprBody();
    return .{
        .location = location,
        .kind = .{ .struc = .{ .fields = fields } },
    };
}

fn parseParExpr(self: *@This()) Error!Expr {
    const start = self.getLocation();
    try self.expect(.parl);
    var expr = try self.parseExprLoud();
    const end = self.getLocation();
    try self.expectLoud(.parr);
    expr.location = start.combine(end);
    return expr;
}

fn parseStructExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const name = try self.parseName();
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
    try self.expect(.curl);
    const fields = try self.parseSep(Expr.Struct.Field, parseNewFieldLoud);
    try self.expect(.curr);
    return fields;
}

fn parseNewFieldLoud(self: *@This()) !Expr.Struct.Field {
    const location = self.getLocation();
    const name = try self.parseNameLoud();
    try self.expectLoud(.equ);
    const expr = try self.parseExprLoud();
    return .{
        .name = name,
        .expr = expr,
        .location = location,
    };
}

fn parseVarExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    const name = try self.parseName();
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
    try self.expect(.undef);
    return .{
        .location = location,
        .kind = .{ .undef = .{} },
    };
}

fn parseTrueExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.tru);
    return .{
        .location = location,
        .kind = .{ .bool = true },
    };
}

fn parseFalseExpr(self: *@This()) Error!Expr {
    const location = self.getLocation();
    try self.expect(.fals);
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

fn parseNameLoud(self: *@This()) ![]const u8 {
    return self.parseName() catch |err| {
        try self.fail("<name>");
        return err;
    };
}

fn parseName(self: *@This()) ![]const u8 {
    return self.parseLexeme(.name);
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
) !@typeInfo(Lexeme).@"union".field_types[@backingInt(tag)] {
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

fn expectLoud(self: *@This(), lexeme: Lexeme) !void {
    self.expect(lexeme) catch |err| {
        try self.fail(lexeme.describe());
        return err;
    };
}

fn expect(self: *@This(), lexeme: @typeInfo(Lexeme).@"union".tag_type.?) !void {
    if (self.tokens[self.cursor].lexeme == lexeme) {
        self.cursor += 1;
    } else {
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
