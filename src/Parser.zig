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
    const typ: okc.Typ = try .parse(self);
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
    const declare: okc.Stmt.Declare.Named = try .parse(self);
    return .{
        .name = declare.name,
        .location = self.tmp_location,
        .kind = .{ .constant = .{ .declare = declare.bare } },
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
    const typ: okc.Item.TypDecl = try .parse(self);
    return .{
        .name = self.tmp_name,
        .location = self.tmp_location,
        .kind = .{ .typ_decl = typ },
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

pub fn parseFieldDecl(self: *@This()) !okc.Item.TypDecl.Field {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.colon, .loud);
    const typ: okc.Typ = try .parse(self);
    const default = try self.maybe(okc.Stmt.Assign.parsePostfix, .{});
    return .{
        .name = name,
        .typ = typ,
        .location = location,
        .default = default,
    };
}

fn parseExtFun(self: *@This()) !okc.Item.Fun.Extern {
    try self.expect(.ext, .quiet);
    const header: okc.Item.Fun.Header = try .parse(self, .loud);
    try self.expect(.semi, .loud);
    return .{
        .header = header,
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

pub fn parseParam(self: *@This()) !okc.Item.Fun.Header.Param {
    const location = self.getLocation();
    const name = try self.parseName(.loud);
    try self.expect(.colon, .loud);
    const typ: okc.Typ = try .parse(self);
    return .{
        .name = name,
        .typ = typ,
        .location = location,
    };
}

pub fn parseFunTyp(self: *@This()) Error!okc.Typ {
    try self.expect(.fun, .quiet);
    try self.expect(.parl, .loud);
    const params = try self.sep(okc.Typ.parse, .{});
    try self.expect(.parr, .loud);
    const ret_typ: okc.Typ = try .parse(self);
    const ptr = try okc.Typ.memo.box(ret_typ, self.arena);
    return .{ .fun = .{
        .params = params,
        .ret_typ = ptr,
    } };
}

pub fn parseGenericTyp(self: *@This()) Error!okc.Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    try self.expect(.les, .quiet);
    const generics = try self.sep(okc.Typ.parse, .{});
    try self.expect(.mor, .loud);
    return .{ .loc_name = .{
        .bare = .{
            .name = name,
            .generics = generics,
        },
        .location = location,
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

pub fn parsePtrTyp(self: *@This()) Error!okc.Typ {
    try self.expect(.amp, .quiet);
    var mutable = false;
    if (try self.maybe(expect, .{ .mut, .quiet })) |_| {
        mutable = true;
    }
    const typ: okc.Typ = try .parse(self);
    const ptr = try okc.Typ.memo.box(typ, self.arena);
    return .{ .ptr = .{
        .typ = ptr,
        .mutable = mutable,
    } };
}

pub fn parseVerbalTyp(self: *@This()) Error!okc.Typ {
    const location = self.getLocation();
    const name = try self.parseName(.quiet);
    return okc.Typ.fromName(name, location);
}

pub fn many(self: *@This(), parse: anytype, args: anytype) ![]ParseRes(parse, args) {
    var vec = std.ArrayList(ParseRes(parse, args)).empty;
    defer vec.deinit(self.gpa);
    return self.manyTo(&vec, parse, args);
}

pub fn manyTo(self: *@This(), vec: anytype, parse: anytype, args: anytype) ![]ParseRes(parse, args) {
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
    const header: okc.Item.Fun.Header = try .parse(self, .quiet);
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

pub fn getLocation(self: @This()) okc.Location {
    return self.tokens[self.cursor].location;
}

pub fn parseName(self: *@This(), mode: Mode) ![]const u8 {
    return try self.maybe(parseLexeme, .{.name}) orelse {
        if (mode == .loud) {
            try self.fail("<name>");
        }
        return error.ParseFailed;
    };
}

pub fn parseInt(self: *@This()) !u64 {
    return self.parseLexeme(.int);
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
