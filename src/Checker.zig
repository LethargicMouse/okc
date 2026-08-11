const std = @import("std");

const Ast = @import("Ast.zig");
const Location = @import("Location.zig");

const ArrayTyp = struct {
    len: []const u8,
    typ: Typ,
};

const Typ = union(enum) {
    prime: Ast.Prime,
    name: []const u8,
    ptr: *const Typ,
    array: *const ArrayTyp,
    err,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| try writer.writeAll(name),
            .ptr => |inner| try writer.print("&{f}", .{inner}),
            .array => |array| try writer.print("[{s}]{f}", .{ array.len, array.typ }),
            .err => try writer.writeAll("<err>"),
        }
    }

    fn isNumber(typ: Typ) bool {
        switch (typ) {
            .prime => |prime| return prime.isNumber(),
            .err => return true,
            else => return false,
        }
    }
};

const Field = struct {
    typ: Typ,
};

const Struct = struct {
    fields: std.StringHashMap(Field),
};

const Var = struct {
    typ: Typ,
    location: Location,
    mutable: bool,
};

const FunTyp = struct {
    params: []const Typ,
    ret_typ: Typ,
};

const Checker = @This();

structs: std.StringHashMap(Struct),
vars: std.StringHashMap(Var),
fun_typs: std.StringHashMap(FunTyp),
arena: std.heap.ArenaAllocator,
ret_typ: Typ = undefined,
errors_cnt: u32 = 0,

pub fn init(gpa: std.mem.Allocator) Checker {
    const structs = std.StringHashMap(Struct).init(gpa);
    const vars = std.StringHashMap(Var).init(gpa);
    const fun_typs = std.StringHashMap(FunTyp).init(gpa);
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .structs = structs,
        .vars = vars,
        .fun_typs = fun_typs,
        .arena = arena,
    };
}

pub fn run(checker: *Checker, ast: Ast) !void {
    defer checker.deinit();
    try checker.checkAst(ast);
    if (checker.errors_cnt == 0) {
        return;
    }
    std.log.err("check failed with {} errors", .{checker.errors_cnt});
    return error.Handled;
}

fn checkAst(checker: *Checker, ast: Ast) !void {
    try checker.regStrStruct();
    for (ast.strucs) |struc| {
        try checker.regStruct(struc);
    }
    for (ast.ext_funs) |ext_fun| {
        try checker.regHeader(ext_fun.header);
    }
    for (ast.funs) |fun| {
        try checker.regHeader(fun.header);
    }
    checker.checkMain();
    for (ast.funs) |fun| {
        try checker.checkFun(fun);
    }
}

fn checkMain(checker: *Checker) void {
    _ = checker.fun_typs.get("main") orelse {
        std.log.err("`main` function not found\n", .{});
        checker.errors_cnt += 1;
        return;
    };
}

fn regHeader(checker: *Checker, header: Ast.Header) !void {
    const params = try checker.arena.allocator().alloc(Typ, header.params.len);
    for (header.params, 0..) |param, i| {
        params[i] = try checker.checkTyp(param.typ);
    }
    const ret_typ = try checker.checkTyp(header.ret_typ);
    try checker.fun_typs.put(header.name, .{
        .params = params,
        .ret_typ = ret_typ,
    });
}

fn checkTyp(checker: *Checker, typ: Ast.Typ) !Typ {
    switch (typ) {
        .prime => |prime| return .{ .prime = prime },
        .name => |name| return .{ .name = name },
        .ptr => |inner| {
            const inner_typ = try checker.checkTyp(inner.*);
            const ptr = try checker.boxTyp(inner_typ);
            return .{ .ptr = ptr };
        },
        .array => |array| {
            const inner_typ = try checker.checkTyp(array.typ);
            const array_typ = try checker.arena.allocator().create(ArrayTyp);
            array_typ.len = array.len;
            array_typ.typ = inner_typ;
            return .{ .array = array_typ };
        },
    }
}

fn regStruct(checker: *Checker, struc: Ast.Struct) !void {
    var res = Struct{
        .fields = std.StringHashMap(Field).init(checker.structs.allocator),
    };
    for (struc.fields) |field| {
        const typ = try checker.checkTyp(field.typ);
        try res.fields.put(field.name, .{
            .typ = typ,
        });
    }
    try checker.structs.put(struc.name, res);
}

fn regStrStruct(checker: *Checker) !void {
    var struc = Struct{
        .fields = std.StringHashMap(Field).init(checker.structs.allocator),
    };
    const u8_ptr = try checker.boxTyp(.{ .prime = .u8 });
    try struc.fields.put("ptr", .{ .typ = .{ .ptr = u8_ptr } });
    try struc.fields.put("len", .{ .typ = .{ .prime = .u64 } });
    try checker.structs.put("str", struc);
}

fn boxTyp(checker: *Checker, typ: Typ) !*Typ {
    const ptr = try checker.arena.allocator().create(Typ);
    ptr.* = typ;
    return ptr;
}

fn checkFun(checker: *Checker, fun: Ast.Fun) !void {
    checker.ret_typ = checker.fun_typs.get(fun.header.name).?.ret_typ;
    for (fun.header.params) |param| {
        try checker.vars.put(param.name, .{
            .typ = try checker.checkTyp(param.typ),
            .location = param.location,
            .mutable = false,
        });
    }
    for (fun.statements) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkStatement(checker: *Checker, statement: Ast.Statement) Error!void {
    switch (statement) {
        .ret => |expr| checker.checkRet(expr),
        .expr => |expr| checker.checkExprStatement(expr),
        .declare => |declare| try checker.checkDeclare(declare, false),
        .assign => |assign| checker.checkAssign(assign),
        .iff => |iff| try checker.checkIf(iff),
        .whi => |whi| try checker.checkWhile(whi),
        .ignore => |expr| _ = checker.checkExpr(expr),
        .mut_declare => |declare| try checker.checkDeclare(declare, true),
    }
}

fn checkExprStatement(checker: *Checker, expr: Ast.Expr) void {
    const typ = checker.checkExpr(expr);
    checker.unify(expr.location(), .{ .prime = .void }, typ);
}

fn checkWhile(checker: *Checker, whi: Ast.While) !void {
    try checker.checkBranch(whi.branch);
}

fn checkIf(checker: *Checker, iff: Ast.If) !void {
    try checker.checkBranch(iff.branch);
    for (iff.else_ifs) |branch| {
        try checker.checkBranch(branch);
    }
    for (iff.else_branch) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkBranch(checker: *Checker, branch: Ast.Branch) !void {
    const typ = checker.checkExpr(branch.condition);
    checker.unify(branch.condition.location(), .{ .prime = .bool }, typ);
    for (branch.statements) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkAssign(checker: *Checker, assign: Ast.Assign) void {
    const typ = checker.checkExpr(assign.expr);
    const vari = checker.vars.get(assign.name).?;
    checker.unify(assign.expr.location(), vari.typ, typ);
    if (!vari.mutable) {
        std.log.err(
            \\in {f}
            \\     item `{s}` is immutable
            \\
        , .{ assign.location, assign.name });
        std.log.info(
            "try inserting `mut` before name in {f}\n",
            .{vari.location},
        );
        checker.errors_cnt += 1;
    }
}

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) void {
    if (canUnify(a, b)) {
        return;
    }
    std.log.err(
        \\in {f}
        \\     wrong type:
        \\         expected  {f}
        \\            found  {f}
        \\
    , .{ location, a, b });
    if (a == .ptr and a.ptr.* == .prime and a.ptr.*.prime == .u8 and b == .name and std.mem.eql(u8, b.name, "str")) {
        std.log.info("append `.ptr` to get C-style string\n", .{});
    }
    checker.errors_cnt += 1;
}

fn canUnify(a: Typ, b: Typ) bool {
    if (a == .err or b == .err) {
        return true;
    }
    if (@intFromEnum(a) != @intFromEnum(b)) {
        return false;
    }
    switch (a) {
        .prime => |aprime| return aprime == b.prime,
        .name => |aname| return std.mem.eql(u8, aname, b.name),
        .ptr => |atyp| return canUnify(atyp.*, b.ptr.*),
        else => unreachable,
    }
}

fn checkDeclare(checker: *Checker, declare: Ast.Declare, mutable: bool) !void {
    const typ = checker.checkExpr(declare.expr);
    try checker.vars.put(declare.name, .{
        .typ = typ,
        .location = declare.location,
        .mutable = mutable,
    });
}

fn checkExpr(checker: *Checker, expr: Ast.Expr) Typ {
    switch (expr) {
        .literal_loc => |literal_loc| return checker.checkLiteralLoc(literal_loc),
        .call => |call| return checker.checkCall(call),
        .binary => |binary| return checker.checkBinary(binary.*),
        .field => |field| return checker.checkField(field.*),
        .struc => |struc| return checker.checkStruc(struc),
    }
}

fn checkStruc(checker: *Checker, struc: Ast.StructExpr) Typ {
    for (struc.fields) |field| {
        _ = checker.checkExpr(field.expr);
    }
    return .{ .name = struc.name };
}

fn checkLiteralLoc(checker: *Checker, literal_loc: Ast.LiteralLoc) Typ {
    switch (literal_loc.literal) {
        .int => |int| return checker.checkInt(literal_loc.location, int),
        .str => return .{ .name = "str" },
        .vari => |name| return checker.checkVar(literal_loc.location, name),
    }
}

fn checkInt(checker: *Checker, location: Location, int: []const u8) Typ {
    _ = std.fmt.parseInt(i64, int, 10) catch {
        std.log.err(
            \\in {f}
            \\     integer is too large
        , .{location});
        checker.errors_cnt += 1;
    };
    return .{ .prime = .i32 };
}

fn checkField(checker: *Checker, field: Ast.Field) Typ {
    const expr_typ = checker.checkExpr(field.expr);
    if (expr_typ == .err) {
        return .err;
    }
    const name = if (expr_typ == .name) expr_typ.name else {
        checker.failNoFields(field.expr.location(), expr_typ);
        return .err;
    };
    const struc = checker.structs.get(name) orelse {
        checker.failNoFields(field.expr.location(), expr_typ);
        return .err;
    };
    const fiel = struc.fields.get(field.name) orelse {
        std.log.err(
            \\in {f}
            \\     no field `{s}` in struct `{s}`
            \\
        , .{ field.location, field.name, name });
        return .err;
    };
    return fiel.typ;
}

fn failNoFields(checker: *Checker, location: Location, typ: Typ) void {
    std.log.err(
        \\in {f}
        \\     type `{f}` does not have fields
        \\
    , .{ location, typ });
    checker.errors_cnt += 1;
}

fn checkBinary(checker: *Checker, binary: Ast.Binary) Typ {
    var left = checker.checkExpr(binary.left);
    if (!left.isNumber()) {
        std.log.err(
            \\in {f}
            \\     wrong type:
            \\         expected  <number>
            \\            found  {f}
        , .{ binary.left.location(), left });
        left = .err;
        checker.errors_cnt += 1;
    }
    const right = checker.checkExpr(binary.right);
    checker.unify(binary.right.location(), left, right);
    switch (binary.op) {
        .equ, .les => return .{ .prime = .bool },
        else => return left,
    }
}

fn checkVar(checker: *Checker, location: Location, name: []const u8) Typ {
    const vari = checker.vars.get(name) orelse {
        var iter = checker.vars.keyIterator();
        while (iter.next()) |vari| {
            if (name.len >= vari.len + 5 and std.mem.startsWith(u8, name, vari.*[0..@min(5, vari.len)])) {
                std.log.err(
                    \\in {f}
                    \\     seems like you've fallen asleep and
                    \\     hit your keyboard while typing `{s}`
                    \\
                    \\     fix it later, time to get some sleep
                , .{ location, vari.* });
                checker.errors_cnt += 1;
                return .err;
            }
        }
        std.log.err(
            \\in {f}
            \\     item `{s}` is not declared
        , .{ location, name });
        checker.errors_cnt += 1;
        return .err;
    };
    return vari.typ;
}

fn checkCall(checker: *Checker, call: Ast.Call) Typ {
    const fun_typ = checker.fun_typs.get(call.name).?;
    for (call.args, fun_typ.params) |arg, param| {
        const typ = checker.checkExpr(arg);
        checker.unify(arg.location(), param, typ);
    }
    return fun_typ.ret_typ;
}

fn checkRet(checker: *Checker, expr: Ast.Expr) void {
    const typ = checker.checkExpr(expr);
    checker.unify(expr.location(), checker.ret_typ, typ);
}

fn deinit(checker: *Checker) void {
    var structs = checker.structs.valueIterator();
    while (structs.next()) |struc| {
        struc.fields.deinit();
    }
    checker.structs.deinit();
    checker.vars.deinit();
    checker.fun_typs.deinit();
    checker.arena.deinit();
    checker.* = undefined;
}

const Error = error{OutOfMemory};
