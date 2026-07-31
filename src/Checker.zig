const std = @import("std");

const Ast = @import("Ast.zig");
const Location = @import("Location.zig");

const Typ = union(enum) {
    prime: Ast.Prime,
    name: []const u8,
    ptr: *const Typ,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| try writer.writeAll(name),
            .ptr => |inner| try writer.print("&{f}", .{inner}),
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
};

const Checker = @This();

structs: std.StringHashMap(Struct),
vars: std.StringHashMap(Var),
fun_ret_typs: std.StringHashMap(Typ),
arena: std.heap.ArenaAllocator,
errors_cnt: u32 = 0,

pub fn init(gpa: std.mem.Allocator) Checker {
    const structs = std.StringHashMap(Struct).init(gpa);
    const vars = std.StringHashMap(Var).init(gpa);
    const fun_ret_typs = std.StringHashMap(Typ).init(gpa);
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .structs = structs,
        .vars = vars,
        .fun_ret_typs = fun_ret_typs,
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
    try checker.makeStrStruct();
    for (ast.ext_funs) |ext_fun| {
        try checker.regHeader(ext_fun.header);
    }
    for (ast.funs) |fun| {
        try checker.regHeader(fun.header);
    }
    for (ast.funs) |fun| {
        try checker.checkFun(fun);
    }
}

fn regHeader(checker: *Checker, header: Ast.Header) !void {
    const typ = try checker.checkTyp(header.ret_typ);
    try checker.fun_ret_typs.put(header.name, typ);
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
    }
}

fn makeStrStruct(checker: *Checker) !void {
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
    for (fun.statements) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkStatement(checker: *Checker, statement: Ast.Statement) Error!void {
    switch (statement) {
        .ret => |expr| checker.checkRet(expr),
        .expr => |expr| _ = checker.checkExpr(expr),
        .let => |let| try checker.checkLet(let),
        .assign => |assign| checker.checkAssign(assign),
        .iff => |iff| try checker.checkIf(iff),
        .whi => |whi| try checker.checkWhile(whi),
    }
}

fn checkWhile(checker: *Checker, whi: Ast.While) !void {
    try checker.checkBranch(whi.branch);
}

fn checkIf(checker: *Checker, iff: Ast.If) !void {
    try checker.checkBranch(iff.cond_branch);
    for (iff.else_ifs) |branch| {
        try checker.checkBranch(branch);
    }
    for (iff.else_branch) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkBranch(checker: *Checker, branch: Ast.Branch) !void {
    _ = checker.checkExpr(branch.condition);
    for (branch.statements) |statement| {
        try checker.checkStatement(statement);
    }
}

fn checkAssign(checker: *Checker, assign: Ast.Assign) void {
    const typ = checker.checkExpr(assign.expr);
    const vari = checker.vars.get(assign.name).?;
    checker.unify(assign.expr.location(), vari.typ, typ);
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
    , .{ location, a, b });
    checker.errors_cnt += 1;
}

fn canUnify(a: Typ, b: Typ) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) {
        return false;
    }
    switch (a) {
        .prime => |aprime| return aprime == b.prime,
        .name => |aname| return std.mem.eql(u8, aname, b.name),
        .ptr => |atyp| return canUnify(atyp.*, b.ptr.*),
    }
}

fn checkLet(checker: *Checker, let: Ast.Let) !void {
    const typ = checker.checkExpr(let.expr);
    try checker.vars.put(let.name, .{
        .typ = typ,
    });
}

fn checkExpr(checker: *Checker, expr: Ast.Expr) Typ {
    switch (expr) {
        .literal_loc => |literal_loc| return checker.checkLiteralLoc(literal_loc),
        .call => |call| return checker.checkCall(call),
        .binary => |binary| return checker.checkBinary(binary.*),
        .field => |field| return checker.checkField(field.*),
    }
}

fn checkLiteralLoc(checker: *Checker, literal_loc: Ast.LiteralLoc) Typ {
    switch (literal_loc.literal) {
        .int => return .{ .prime = .i32 },
        .str => return .{ .name = "str" },
        .vari => |name| return checker.checkVar(name),
    }
}

fn checkField(checker: *Checker, field: Ast.Field) Typ {
    const expr_typ = checker.checkExpr(field.expr);
    const struc = checker.structs.get(expr_typ.name).?;
    const fiel = struc.fields.get(field.name).?;
    return fiel.typ;
}

fn checkBinary(checker: *Checker, binary: Ast.Binary) Typ {
    const typ = checker.checkExpr(binary.left);
    _ = checker.checkExpr(binary.right);
    return typ;
}

fn checkVar(checker: *Checker, name: []const u8) Typ {
    const vari = checker.vars.get(name).?;
    return vari.typ;
}

fn checkCall(checker: *Checker, call: Ast.Call) Typ {
    for (call.args) |arg| {
        _ = checker.checkExpr(arg);
    }
    const typ = checker.fun_ret_typs.get(call.name).?;
    return typ;
}

fn checkRet(checker: *Checker, expr: Ast.Expr) void {
    _ = checker.checkExpr(expr);
}

fn deinit(checker: *Checker) void {
    var structs = checker.structs.valueIterator();
    while (structs.next()) |struc| {
        struc.fields.deinit();
    }
    checker.structs.deinit();
    checker.vars.deinit();
    checker.fun_ret_typs.deinit();
    checker.arena.deinit();
    checker.* = undefined;
}

const Error = error{OutOfMemory};
