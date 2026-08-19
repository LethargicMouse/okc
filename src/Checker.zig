const std = @import("std");

const Ast = @import("Ast.zig");
const Location = @import("Location.zig");
const Info = @import("Info.zig");
const Typ = Info.Typ;

const Error = error{OutOfMemory};

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

const LazyStruct = struct {
    typ: *const Typ,
    fields: []const Ast.NewField,
    typs: []const Typ,
    location: Location,
};

const Checker = @This();

gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
structs: std.StringHashMap(Struct),
vars: std.StringHashMap(Var),
fun_typs: std.StringHashMap(FunTyp),
lazy_strucs: std.ArrayList(LazyStruct) = .empty,
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
        .gpa = gpa,
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
    checker.info.deinit();
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
    checker.checkMain(ast.location);
}

fn checkVars(checker: *Checker) void {
    var iter = checker.vars.valueIterator();
    while (iter.next()) |vari| {
        if (vari.mutable and !vari.mutated) {
            checker.fail(
                \\in {f}
                \\     variable is never mutated
            , .{vari.location});
            std.log.info("remove `mut` before name\n", .{});
        }
    }
}

fn checkMain(checker: *Checker, location: Location) void {
    _ = checker.fun_typs.get("main") orelse {
        checker.fail(
            \\in {f}
            \\     `main` function not found
        , .{location});
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
    try checker.regStruct(Ast.str_struct);
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
        checker.fail(
            \\in {f}
            \\     function may not return
        , .{fun.header.location});
    }
    for (checker.lazy_strucs.items) |lazy_struc| {
        const name = switch (lazy_struc.typ.*) {
            .name => |name| name,
            .any => {
                checker.fail(
                    \\in {f}
                    \\     cannot infer type
                , .{lazy_struc.location});
                continue;
            },
            else => {
                checker.fail(
                    \\in {f}
                    \\     wrong type:
                    \\         expected  {f}
                    \\            found  <struct>
                , .{ lazy_struc.location, lazy_struc.typ });
                continue;
            },
        };
        checker.checkStrucNow(lazy_struc.location, .{
            .name = name,
            .fields = lazy_struc.fields,
        }, lazy_struc.typs);
    }
    checker.lazy_strucs.clearRetainingCapacity();
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
                checker.fail(
                    \\in {f}
                    \\     statement is unreachable
                , .{block[i + 1].location});
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
        .ignore => |ignore| return checker.checkIgnore(ignore, statement.location),
        .mut_declare => |declare| {
            return checker.checkDeclare(declare, statement.location, true);
        },
    }
}

fn checkIgnore(checker: *Checker, ignore: Ast.Ignore, location: Location) !ControlFlow {
    const typ = try checker.checkExpr(ignore.expr);
    if (typ == .prime and typ.prime == .void) {
        checker.fail(
            \\in {f}
            \\     redundant ignore
        , .{location});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}

fn checkBreak(checker: *Checker, location: Location) Error!ControlFlow {
    if (checker.loops_nested == 0) {
        checker.fail(
            \\in {f}
            \\     `break` outside of loop
        , .{location});
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
        .int,
        .str,
        .char,
        .undef,
        .bool,
        .call,
        .binary,
        .struc,
        .ptr,
        .notb,
        .infer_struc,
        => {
            const typ = try checker.checkExpr(expr);
            checker.failAssignConst(expr.location);
            return typ;
        },
    }
}

fn failAssignConst(checker: *Checker, location: Location) void {
    checker.fail(
        \\in {f}
        \\     cannot assign to constant
    , .{location});
}

fn checkElem(checker: *Checker, elem: Ast.Elem, location: Location, mutable: bool) !Typ {
    const typ = try checker.checkExprWith(elem.expr, mutable);
    const red = typ.normalise();
    switch (red) {
        .array => |array| return array.typ,
        .err => return .err,
        .prime, .name, .ptr, .any, .int => {
            checker.fail(
                \\in {f}
                \\     type `{f}` does not support indexing
            , .{ location, typ });
            return .err;
        },
        .lazy => unreachable,
    }
}

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) void {
    if (canUnify(a, b, true)) {
        return;
    }
    checker.fail(
        \\in {f}
        \\     wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ location, a, b });
    if (a == .ptr and a.ptr.* == .prime and a.ptr.*.prime == .u8 and b == .name and std.mem.eql(u8, b.name, "str")) {
        std.log.info("append `.ptr` to get C-style string\n", .{});
    }
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
        .infer_struc => |struc| return checker.checkInferStruc(struc, expr.location),
        .int => |int| return checker.checkInt(expr.location, int),
        .str => return .{ .name = "str" },
        .vari => |name| return checker.checkVar(expr.location, name, false),
        .char => return .{ .prime = .u8 },
        .bool => return .{ .prime = .bool },
        .undef => |undef| return checker.checkUndef(undef),
        .call => |call| return checker.checkCall(call, expr.location),
        .binary => |binary| return checker.checkBinary(binary.*),
        .field => |field| return checker.checkField(field.*, expr.location, false),
        .struc => |struc| return checker.checkStruc(struc, expr.location),
        .ptr => |ptr| return checker.checkPtr(ptr.*),
        .notb => |notb| return checker.checkNotb(notb.*),
        .elem => |elem| return checker.checkElem(elem.*, expr.location, false),
    }
}

fn checkNotb(checker: *Checker, notb: Ast.Notb) !Typ {
    const typ = try checker.checkExpr(notb.expr);
    checker.unify(notb.expr.location, .int, typ);
    return typ;
}

fn checkPtr(checker: *Checker, ptr: Ast.Ptr) !Typ {
    const typ = try checker.arena.allocator().create(Typ);
    typ.* = try checker.checkExprMut(ptr.expr);
    return .{ .ptr = typ };
}

fn checkInferStruc(checker: *Checker, struc: Ast.InferStruct, location: Location) !Typ {
    const typs = try checker.arena.allocator().alloc(Typ, struc.fields.len);
    for (struc.fields, typs) |field, *typ| {
        typ.* = try checker.checkExpr(field.expr);
    }
    const lazy = try checker.arena.allocator().create(Typ);
    lazy.* = .any;
    checker.info.typs[struc.typ_id] = lazy;
    try checker.lazy_strucs.append(checker.gpa, .{
        .typ = lazy,
        .fields = struc.fields,
        .typs = typs,
        .location = location,
    });
    return .{ .lazy = lazy };
}

fn checkStruc(checker: *Checker, struc: Ast.StructExpr, location: Location) !Typ {
    const typs = try checker.arena.allocator().alloc(Typ, struc.fields.len);
    for (struc.fields, typs) |field, *typ| {
        typ.* = try checker.checkExpr(field.expr);
    }
    checker.checkStrucNow(location, struc, typs);
    return .{ .name = struc.name };
}

fn checkStrucNow(
    checker: *Checker,
    location: Location,
    struc: Ast.StructExpr,
    typs: []const Typ,
) void {
    const decl = checker.structs.get(struc.name) orelse {
        checker.failNotStruct(location, .{ .name = struc.name });
        return;
    };
    for (struc.fields, typs) |field, typ| {
        const f_decl = decl.fields.get(field.name) orelse {
            checker.failNoField(field.location, field.name, struc.name);
            continue;
        };
        checker.unify(field.expr.location, f_decl.typ, typ);
    }
    var iter = decl.fields.keyIterator();
    while (iter.next()) |field_decl| {
        var unused = true;
        for (struc.fields) |field| {
            if (std.mem.eql(u8, field_decl.*, field.name)) {
                unused = false;
                break;
            }
        }
        if (unused) {
            checker.fail(
                \\in {f}
                \\     field `{s}` is not initialized
            , .{ location, field_decl.* });
        }
    }
}

fn checkUndef(checker: *Checker, undef: Ast.Undef) !Typ {
    const typ = try checker.arena.allocator().create(Typ);
    typ.* = .any;
    checker.info.typs[undef.typ_id] = typ;
    return .{ .lazy = typ };
}

fn checkInt(checker: *Checker, location: Location, int: []const u8) Typ {
    _ = std.fmt.parseInt(u64, int, 10) catch {
        checker.fail(
            \\in {f}
            \\     integer is too large
        , .{location});
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
        checker.failNotStruct(field.expr.location, expr_typ);
        return .err;
    };
    const struc = checker.structs.get(name) orelse {
        checker.failNotStruct(field.expr.location, expr_typ);
        return .err;
    };
    const fiel = struc.fields.get(field.name) orelse {
        checker.failNoField(location, field.name, name);
        return .err;
    };
    return fiel.typ;
}

fn failNoField(
    checker: *Checker,
    location: Location,
    field: []const u8,
    struc: []const u8,
) void {
    checker.fail(
        \\in {f}
        \\     no field `{s}` in struct `{s}`
    , .{ location, field, struc });
}

fn failNotStruct(checker: *Checker, location: Location, typ: Typ) void {
    checker.fail(
        \\in {f}
        \\     type `{f}` is not a struct
    , .{ location, typ });
}

fn checkBinary(checker: *Checker, binary: Ast.Binary) !Typ {
    var left = try checker.checkExpr(binary.left);
    if (!left.isNumber()) {
        checker.fail(
            \\in {f}
            \\     wrong type:
            \\         expected  <number>
            \\            found  {f}
        , .{ binary.left.location, left });
        left = .err;
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
        checker.fail(
            \\in {f}
            \\     item `{s}` is not declared
        , .{ location, name });
        return .err;
    };
    if (mutable) {
        if (vari.mutable) {
            vari.mutated = true;
        } else {
            checker.failAssignConst(location);
            std.log.info("add `mut` before name in {f}\n", .{vari.location});
        }
    }
    return vari.typ;
}

fn checkCall(checker: *Checker, call: Ast.Call, location: Location) !Typ {
    const fun_typ = checker.fun_typs.get(call.name) orelse {
        checker.fail(
            \\in {f}
            \\     item `{s}` is not declared
        , .{ location, call.name });
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
    checker.lazy_strucs.deinit(checker.gpa);
    checker.* = undefined;
}

fn fail(checker: *Checker, comptime msg: []const u8, args: anytype) void {
    std.log.err(msg ++ "\n", args);
    checker.errors_cnt += 1;
}
