const std = @import("std");

const Ast = @import("Ast.zig");
const Location = @import("Location.zig");
const Info = @import("Info.zig");
const Typ = Info.Typ;

// numbered to enable `<`
const ControlFlow = enum(u2) {
    cont = 0,
    brek = 1,
    ret = 2,
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
    mutated: bool = false,
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
info: Info,
ret_typ: Typ = undefined,
errors_cnt: u16 = 0,
loops_nested: u16 = 0,

pub fn init(gpa: std.mem.Allocator, ast_info: Ast.Info) !Checker {
    const structs = std.StringHashMap(Struct).init(gpa);
    const vars = std.StringHashMap(Var).init(gpa);
    const fun_typs = std.StringHashMap(FunTyp).init(gpa);
    const arena = std.heap.ArenaAllocator.init(gpa);
    const info = try Info.init(gpa, ast_info);
    return .{
        .structs = structs,
        .vars = vars,
        .fun_typs = fun_typs,
        .arena = arena,
        .info = info,
    };
}

pub fn run(checker: *Checker, ast: Ast) !Info {
    defer checker.deinit();
    try checker.checkAst(ast);
    if (checker.errors_cnt == 0) {
        return checker.info;
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
    for (ast.funs) |fun| {
        try checker.checkFun(fun);
    }
    checker.checkVars();
    checker.checkMain();
}

fn checkVars(checker: *Checker) void {
    var iter = checker.vars.valueIterator();
    while (iter.next()) |vari| {
        if (vari.mutable and !vari.mutated) {
            std.log.err(
                \\in {f}
                \\     variable is never mutated
                \\
            , .{vari.location});
            std.log.info("remove `mut` before name\n", .{});
            checker.errors_cnt += 1;
        }
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
            const array_typ = try checker.arena.allocator().create(Typ.Array);
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
    const cf = try checker.checkBlock(fun.body);
    if (cf != .ret and !fun.header.ret_typ.isVoid()) {
        std.log.err(
            \\in {f}
            \\     function may not return
            \\
        , .{fun.header.location});
        checker.errors_cnt += 1;
    }
}

fn checkBlock(checker: *Checker, block: []const Ast.Statement) !ControlFlow {
    var res = ControlFlow.cont;
    for (0..block.len) |i| {
        const cf = try checker.checkStatement(block[i]);
        if (cf != .cont) {
            if (res == .cont) {
                res = cf;
            }
            if (i + 1 != block.len) {
                std.log.err(
                    \\in {f}
                    \\     statement is unreachable
                    \\
                , .{block[i + 1].location});
                checker.errors_cnt += 1;
            }
        }
    }
    return res;
}

fn checkStatement(checker: *Checker, statement: Ast.Statement) Error!ControlFlow {
    switch (statement.kind) {
        .unre => return .ret,
        .brek => return checker.checkBreak(statement.location),
        .ret => |ret| return checker.checkRet(ret),
        .expr => |expr| return checker.checkExprStatement(expr),
        .declare => |declare| {
            return checker.checkDeclare(declare, statement.location, false);
        },
        .assign => |assign| return checker.checkAssign(assign),
        .iff => |iff| return checker.checkIf(iff),
        .whi => |whi| return checker.checkWhile(whi),
        .ignore => |ignore| return checker.checkIgnore(ignore),
        .mut_declare => |declare| {
            return checker.checkDeclare(declare, statement.location, true);
        },
    }
}

fn checkIgnore(checker: *Checker, ignore: Ast.Ignore) !ControlFlow {
    _ = try checker.checkExpr(ignore.expr);
    return .cont;
}

fn checkBreak(checker: *Checker, location: Location) Error!ControlFlow {
    if (checker.loops_nested == 0) {
        std.log.err(
            \\in {f}
            \\     `break` outside of loop
            \\
        , .{location});
        checker.errors_cnt += 1;
        return .cont;
    }
    return .brek;
}

fn checkExprStatement(checker: *Checker, expr: Ast.Expr) !ControlFlow {
    const typ = try checker.checkExpr(expr);
    checker.unify(expr.location, .{ .prime = .void }, typ);
    return .cont;
}

fn checkWhile(checker: *Checker, whi: Ast.While) !ControlFlow {
    const cf = try checker.checkBranch(whi.branch, true);
    switch (cf) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}

fn checkIf(checker: *Checker, iff: Ast.If) !ControlFlow {
    var res = try checker.checkBranch(iff.branch, false);
    for (iff.else_ifs) |branch| {
        const cf = try checker.checkBranch(branch, false);
        if (@intFromEnum(cf) < @intFromEnum(res)) {
            res = cf;
        }
    }
    const cf = try checker.checkBlock(iff.else_branch);
    if (@intFromEnum(cf) < @intFromEnum(res)) {
        res = cf;
    }
    return res;
}

fn checkBranch(checker: *Checker, branch: Ast.Branch, loop: bool) !ControlFlow {
    const typ = try checker.checkExpr(branch.condition);
    checker.unify(branch.condition.location, .{ .prime = .bool }, typ);
    if (loop) {
        checker.loops_nested += 1;
    }
    const cf = try checker.checkBlock(branch.body);
    if (loop) {
        checker.loops_nested -= 1;
    }
    return cf;
}

fn checkAssign(checker: *Checker, assign: Ast.Assign) !ControlFlow {
    const typ = try checker.checkExpr(assign.expr);
    const left_typ = try checker.checkExprMut(assign.left);
    checker.unify(assign.expr.location, left_typ, typ);
    return .cont;
}

fn checkExprMut(checker: *Checker, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .vari => |name| return checker.checkVar(expr.location, name, true),
        .field => |field| return checker.checkField(field.*, expr.location, true),
        .elem => |elem| return checker.checkElem(elem.*, expr.location, true),
        .int, .str, .char, .undef, .bool, .call, .binary, .struc, .ptr, .notb => {
            const typ = try checker.checkExpr(expr);
            std.log.err(
                \\in {f}
                \\     cannot assign to constant
                \\
            , .{expr.location});
            checker.errors_cnt += 1;
            return typ;
        },
    }
}

fn checkElem(checker: *Checker, elem: Ast.Elem, location: Location, mutable: bool) !Typ {
    const typ = try checker.checkExprWith(elem.expr, mutable);
    const red = typ.normalise();
    switch (red) {
        .array => |array| return array.typ,
        .err => return .err,
        .prime, .name, .ptr, .any, .int => {
            std.log.err(
                \\in {f}
                \\     type `{f}` does not support indexing
                \\
            , .{ location, typ });
            checker.errors_cnt += 1;
            return .err;
        },
        .lazy => unreachable,
    }
}

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) void {
    if (canUnify(a, b, true)) {
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

fn canUnify(a: Typ, b: Typ, active: bool) bool {
    if (a == .err or b == .err) {
        return true;
    }
    if (a == .any or b == .any) {
        return true;
    }
    if (a == .int and b.isNumber() or b == .int and a.isNumber()) {
        return true;
    }
    if (b == .lazy) {
        const res = canUnify(a, b.lazy.*, active);
        if (res and active) {
            b.lazy.* = a;
        }
        return res;
    }
    if (@intFromEnum(a) != @intFromEnum(b)) {
        return false;
    }
    switch (a) {
        .prime => |aprime| return aprime == b.prime,
        .name => |aname| return std.mem.eql(u8, aname, b.name),
        .ptr => |atyp| return canUnify(atyp.*, b.ptr.*, active),
        else => unreachable,
    }
}

fn checkDeclare(
    checker: *Checker,
    declare: Ast.Declare,
    location: Location,
    mutable: bool,
) !ControlFlow {
    const expr_typ = try checker.checkExpr(declare.expr);
    var typ = expr_typ;
    if (declare.typ) |typ_decl| {
        const decl_typ = try checker.checkTyp(typ_decl);
        checker.unify(declare.expr.location, decl_typ, expr_typ);
        // if expr_typ is `<any>`
        typ = decl_typ;
    }
    try checker.vars.put(declare.name, .{
        .typ = typ,
        .location = location,
        .mutable = mutable,
    });
    return .cont;
}

fn checkExpr(checker: *Checker, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .int => |int| return checker.checkInt(expr.location, int),
        .str => return .{ .name = "str" },
        .vari => |name| return checker.checkVar(expr.location, name, false),
        .char => return .{ .prime = .u8 },
        .bool => return .{ .prime = .bool },
        .undef => |undef| return checker.checkUndef(undef),
        .call => |call| return checker.checkCall(call, expr.location),
        .binary => |binary| return checker.checkBinary(binary.*),
        .field => |field| return checker.checkField(field.*, expr.location, false),
        .struc => |struc| return checker.checkStruc(struc),
        .ptr => |ptr| return checker.checkPtr(ptr.*),
        .notb => |notb| return checker.checkNotb(notb.*),
        .elem => |elem| return checker.checkElem(elem.*, expr.location, false),
    }
}

fn checkNotb(checker: *Checker, notb: Ast.Notb) !Typ {
    const typ = try checker.checkExpr(notb.expr);
    return typ;
}

fn checkPtr(checker: *Checker, ptr: Ast.Ptr) !Typ {
    const typ = try checker.arena.allocator().create(Typ);
    typ.* = try checker.checkExprMut(ptr.expr);
    return .{ .ptr = typ };
}

fn checkStruc(checker: *Checker, struc: Ast.StructExpr) !Typ {
    for (struc.fields) |field| {
        _ = try checker.checkExpr(field.expr);
    }
    return .{ .name = struc.name };
}

fn checkUndef(checker: *Checker, undef: Ast.Undef) !Typ {
    const typ = try checker.arena.allocator().create(Typ);
    typ.* = .any;
    checker.info.typs[undef.typ_id] = typ;
    return .{ .lazy = typ };
}

fn checkInt(checker: *Checker, location: Location, int: []const u8) Typ {
    _ = std.fmt.parseInt(u64, int, 10) catch {
        std.log.err(
            \\in {f}
            \\     integer is too large
            \\
        , .{location});
        checker.errors_cnt += 1;
    };
    return .int;
}

fn checkExprWith(checker: *Checker, expr: Ast.Expr, mutable: bool) !Typ {
    if (mutable) {
        return checker.checkExprMut(expr);
    }
    return checker.checkExpr(expr);
}

fn checkField(checker: *Checker, field: Ast.Field, location: Location, mutable: bool) !Typ {
    const expr_typ = try checker.checkExprWith(field.expr, mutable);
    if (expr_typ == .err) {
        return .err;
    }
    const norm = expr_typ.normalise();
    const name = if (norm == .name) norm.name else {
        checker.failNoFields(field.expr.location, expr_typ);
        return .err;
    };
    const struc = checker.structs.get(name) orelse {
        checker.failNoFields(field.expr.location, expr_typ);
        return .err;
    };
    const fiel = struc.fields.get(field.name) orelse {
        std.log.err(
            \\in {f}
            \\     no field `{s}` in struct `{s}`
            \\
        , .{ location, field.name, name });
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

fn checkBinary(checker: *Checker, binary: Ast.Binary) !Typ {
    var left = try checker.checkExpr(binary.left);
    if (!left.isNumber()) {
        std.log.err(
            \\in {f}
            \\     wrong type:
            \\         expected  <number>
            \\            found  {f}
            \\
        , .{ binary.left.location, left });
        left = .err;
        checker.errors_cnt += 1;
    }
    const right = try checker.checkExpr(binary.right);
    checker.unify(binary.right.location, left, right);
    switch (binary.op) {
        .equ, .les => return .{ .prime = .bool },
        else => return left,
    }
}

fn checkVar(checker: *Checker, location: Location, name: []const u8, mutable: bool) Typ {
    const vari = checker.vars.getPtr(name) orelse {
        std.log.err(
            \\in {f}
            \\     item `{s}` is not declared
            \\
        , .{ location, name });
        checker.errors_cnt += 1;
        return .err;
    };
    if (mutable) {
        if (vari.mutable) {
            vari.mutated = true;
        } else {
            std.log.err(
                \\in {f}
                \\     cannot assign to constant
                \\
            , .{location});
            checker.errors_cnt += 1;
            std.log.info("add `mut` before name in {f}\n", .{vari.location});
        }
    }
    return vari.typ;
}

fn checkCall(checker: *Checker, call: Ast.Call, location: Location) !Typ {
    const fun_typ = checker.fun_typs.get(call.name) orelse {
        std.log.err(
            \\in {f}
            \\     item `{s}` is not declared
            \\
        , .{ location, call.name });
        checker.errors_cnt += 1;
        for (call.args) |arg| {
            _ = try checker.checkExpr(arg);
        }
        return .err;
    };
    for (call.args, fun_typ.params) |arg, param| {
        const typ = try checker.checkExpr(arg);
        checker.unify(arg.location, param, typ);
    }
    return fun_typ.ret_typ;
}

fn checkRet(checker: *Checker, ret: Ast.Return) !ControlFlow {
    const typ = try checker.checkExpr(ret.expr);
    checker.unify(ret.expr.location, checker.ret_typ, typ);
    return .ret;
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
