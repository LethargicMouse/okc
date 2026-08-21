const std = @import("std");

const Ast = @import("Ast.zig");
const builtin = @import("builtin.zig");
const Info = @import("Info.zig");
const LlvmTyps = @import("LlvmTyps.zig");
const LlvmTyp = LlvmTyps.Typ;
const Location = @import("Location.zig");
const Typs = @import("Typs.zig");
const Typ = Typs.Typ;

const Error = error{OutOfMemory};

// numbered to enable `<`
const ControlFlow = enum(u2) {
    cont = 0,
    brek = 1,
    ret = 2,
};

const Field = struct {
    location: Location,
    typ: Typ,
};

const Struct = struct {
    fields: std.StringHashMap(Field),
    location: Location,
};

const Var = struct {
    typ: Typ,
    location: Location,
    can_be_mutable: bool,
    mutable: bool,
    mutated: bool = false,
    used: bool = false,
};

const Header = struct {
    params: []const Typ,
    ret_typ: Typ,
    location: Location,
    used: bool = false,
};

const LazyStruct = struct {
    typ: *const Typ,
    fields: []const Ast.NewField,
    typs: []const Typ,
    location: Location,
};

const Lazy = struct {
    typ: *const Typ,
    location: Location,
};

const Checker = @This();

gpa: std.mem.Allocator,
typs: Typs,
fun_arena: std.heap.ArenaAllocator,
structs: std.StringHashMap(Struct),
vars: std.StringHashMap(Var),
vars_stack: std.ArrayList([]const u8) = .empty,
headers: std.StringHashMap(Header),
lazy_strucs: std.ArrayList(LazyStruct) = .empty,
lazies: []Lazy,
info: Info,
ret_typ: Typ = undefined,
errors_cnt: u16 = 0,
loops_nested: u16 = 0,

pub fn init(
    gpa: std.mem.Allocator,
    llvm_typs: *LlvmTyps,
    ast_info: Ast.Info,
) !Checker {
    const structs = std.StringHashMap(Struct).init(gpa);
    const vars = std.StringHashMap(Var).init(gpa);
    const headers = std.StringHashMap(Header).init(gpa);
    var global_typs = Typs.init(gpa);
    const info = try Info.init(llvm_typs, ast_info);
    const fun_arena = std.heap.ArenaAllocator.init(gpa);
    const lazies = try global_typs.arena.allocator().alloc(Lazy, ast_info.typ_ids);
    return .{
        .gpa = gpa,
        .fun_arena = fun_arena,
        .structs = structs,
        .vars = vars,
        .headers = headers,
        .typs = global_typs,
        .info = info,
        .lazies = lazies,
    };
}

pub fn run(checker: *Checker, ast: Ast, llvm_typs: *LlvmTyps) !Info {
    defer checker.deinit();
    try checker.checkAst(ast, llvm_typs);
    if (checker.errors_cnt == 0) {
        return checker.info;
    }
    std.log.err("check failed with {} errors", .{checker.errors_cnt});
    return error.Handled;
}

fn checkAst(checker: *Checker, ast: Ast, llvm_typs: *LlvmTyps) !void {
    try checker.regStrStruct();
    for (ast.items) |item| {
        try checker.regItem(item);
    }
    for (ast.items) |item| {
        try checker.checkItem(item);
    }
    checker.checkVars();
    checker.checkMain(ast.location);
    checker.checkHeaders();
    try checker.checkLazyTyps(llvm_typs);
}

fn checkLazyTyps(checker: *Checker, llvm_typs: *LlvmTyps) !void {
    for (checker.lazies, checker.info.typs) |lazy, *target| {
        target.* = checker.convertTyp(lazy.typ.*, lazy.location, llvm_typs) catch |err| switch (err) {
            error.BadConvert => continue,
            else => return err,
        };
    }
}

fn convertTyp(checker: *Checker, typ: Typ, location: Location, llvm_typs: *LlvmTyps) !LlvmTyp {
    switch (typ) {
        .name => |name| return .{ .name = name },
        .prime => |prime| return LlvmTyp.fromPrime(prime),
        .ptr => |ptr| {
            const inner = try checker.convertTyp(ptr.*, location, llvm_typs);
            const new = try llvm_typs.box(inner);
            return .{ .ptr = new };
        },
        .mut_ptr => |ptr| {
            const inner = try checker.convertTyp(ptr.*, location, llvm_typs);
            const new = try llvm_typs.box(inner);
            return .{ .ptr = new };
        },
        .array => |array| {
            const inner = try checker.convertTyp(array.typ.*, location, llvm_typs);
            const new = try llvm_typs.box(inner);
            return .{ .array = .{
                .len = array.len,
                .typ = new,
            } };
        },
        .err => return error.BadConvert,
        .any, .int => {
            checker.failShouldKnowTyp(location);
            return error.BadConvert;
        },
        .lazy => |inner| return checker.convertTyp(inner.*, location, llvm_typs),
    }
}

fn checkHeaders(checker: *Checker) void {
    var iter = checker.headers.valueIterator();
    while (iter.next()) |header| {
        if (!header.used) {
            checker.failUnused(header.location);
        }
    }
}

fn regItem(checker: *Checker, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => |ext_fun| try checker.regHeader(ext_fun.header),
        .struc => |struc| try checker.regStruct(struc),
        .fun => |fun| try checker.regHeader(fun.header),
    }
}

fn checkItem(checker: *Checker, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => {},
        .struc => {},
        .fun => |fun| try checker.checkFun(fun),
    }
}

fn checkVars(checker: *Checker) void {
    var iter = checker.vars.valueIterator();
    while (iter.next()) |vari| {
        if (!vari.used) {
            checker.failUnused(vari.location);
        } else if (vari.mutable and !vari.mutated) {
            checker.fail(vari.location, "variable is never mutated", .{});
            std.log.info("remove `mut` before name\n", .{});
        }
    }
}

fn failUnused(checker: *Checker, location: Location) void {
    checker.fail(location, "item is never used", .{});
}

fn checkMain(checker: *Checker, location: Location) void {
    const header = checker.headers.getPtr("main") orelse {
        checker.fail(location, "`main` function not found", .{});
        return;
    };
    header.used = true;
}

fn regHeader(checker: *Checker, header: Ast.Header) !void {
    if (checker.headers.get(header.name)) |prev| {
        checker.failAlreadyDeclared(
            header.location,
            "function",
            header.name,
            prev.location,
        );
        return;
    }
    const params = try checker.typs.arena.allocator().alloc(Typ, header.params.len);
    for (header.params, 0..) |param, i| {
        params[i] = try checker.typs.makeTyp(param.typ);
    }
    const ret_typ = try checker.typs.makeTyp(header.ret_typ);
    try checker.headers.put(header.name, .{
        .params = params,
        .ret_typ = ret_typ,
        .location = header.location,
    });
}

fn failAlreadyDeclared(
    checker: *Checker,
    location: Location,
    kind: []const u8,
    name: []const u8,
    prev: Location,
) void {
    checker.fail(
        location,
        "{s} `{s}` is already declared in {f}",
        .{ kind, name, prev },
    );
}

fn regStruct(checker: *Checker, struc: Ast.Struct) !void {
    if (checker.structs.get(struc.name)) |prev| {
        checker.failAlreadyDeclared(struc.location, "struct", struc.name, prev.location);
        return;
    }
    var res = Struct{
        .fields = std.StringHashMap(Field).init(checker.structs.allocator),
        .location = struc.location,
    };
    for (struc.fields) |field| {
        if (res.fields.get(field.name)) |prev| {
            checker.failAlreadyDeclared(field.location, "field", field.name, prev.location);
            continue;
        }
        const typ = try checker.typs.makeTyp(field.typ);
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = typ,
        });
    }
    try checker.structs.put(struc.name, res);
}

fn regStrStruct(checker: *Checker) !void {
    try checker.regStruct(builtin.str_struct);
}

fn checkFun(checker: *Checker, fun: Ast.Fun) !void {
    checker.ret_typ = checker.headers.get(fun.header.name).?.ret_typ;
    for (fun.header.params) |param| {
        if (checker.vars.get(param.name)) |prev| {
            checker.failAlreadyDeclared(param.location, "item", param.name, prev.location);
            continue;
        }
        try checker.vars.put(param.name, .{
            .typ = try checker.typs.makeTyp(param.typ),
            .location = param.location,
            .mutable = false,
            .can_be_mutable = false,
        });
    }
    const cf = try checker.checkBlock(fun.body);
    if (cf != .ret and !fun.header.ret_typ.isVoid()) {
        checker.fail(fun.header.location, "function may not return", .{});
    }
    for (checker.lazy_strucs.items) |lazy_struc| {
        const name = switch (lazy_struc.typ.*) {
            .name => |name| name,
            .any => {
                checker.fail(lazy_struc.location, "cannot infer type", .{});
                continue;
            },
            else => {
                checker.failWrongTyp(lazy_struc.location, lazy_struc.typ.*, .err);
                continue;
            },
        };
        try checker.checkStrucNow(lazy_struc.location, .{
            .name = name,
            .fields = lazy_struc.fields,
        }, lazy_struc.typs);
    }
    checker.lazy_strucs.clearRetainingCapacity();
    checker.vars.clearRetainingCapacity();
    _ = checker.fun_arena.reset(.retain_capacity);
}

fn checkBlock(checker: *Checker, block: []const Ast.Statement) !ControlFlow {
    var res = ControlFlow.cont;
    const rbp = checker.vars_stack.items.len;
    for (0..block.len) |i| {
        const cf = try checker.checkStatement(block[i]);
        if (cf != .cont) {
            if (res == .cont) {
                res = cf;
            }
            if (i + 1 != block.len) {
                checker.fail(block[i + 1].location, "statement is unreachable", .{});
            }
        }
    }
    for (checker.vars_stack.items[rbp..]) |name| {
        const was = checker.vars.remove(name);
        std.debug.assert(was);
    }
    checker.vars_stack.shrinkRetainingCapacity(rbp);
    return res;
}

fn checkStatement(checker: *Checker, statement: Ast.Statement) Error!ControlFlow {
    switch (statement.kind) {
        .unre => return .ret,
        .brek => return checker.checkBreak(statement.location),
        .ret => |ret| return checker.checkRet(ret, statement.location),
        .expr => |expr| return checker.checkExprStatement(expr),
        .declare => |declare| {
            return checker.checkDeclare(declare, statement.location, false);
        },
        .op_assign => |op_assign| return checker.checkOpAssign(op_assign),
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
        checker.fail(location, "redundant ignore", .{});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}

fn checkBreak(checker: *Checker, location: Location) Error!ControlFlow {
    if (checker.loops_nested == 0) {
        checker.fail(location, "`break` outside of loop", .{});
        return .cont;
    }
    return .brek;
}

fn checkExprStatement(checker: *Checker, expr: Ast.Expr) !ControlFlow {
    const typ = try checker.checkExpr(expr);
    try checker.unify(expr.location, .{ .prime = .void }, typ);
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
    try checker.unify(branch.condition.location, .{ .prime = .bool }, typ);
    if (loop) {
        checker.loops_nested += 1;
    }
    const cf = try checker.checkBlock(branch.body);
    if (loop) {
        checker.loops_nested -= 1;
    }
    return cf;
}

fn checkOpAssign(checker: *Checker, op_assign: Ast.OpAssign) !ControlFlow {
    var left = try checker.checkExprMut(op_assign.left);
    const right = try checker.checkExpr(op_assign.right);
    switch (op_assign.kind) {
        .add, .andb, .div, .mul, .orb, .rem, .sub => {
            if (!left.isNumber()) {
                checker.failWrongTyp(op_assign.left.location, .int, left);
                left = .err;
            }
        },
        .equ, .les => {
            try checker.unify(op_assign.left.location, .{ .prime = .bool }, right);
        },
    }
    try checker.unify(op_assign.right.location, left, right);
    return .cont;
}

fn checkAssign(checker: *Checker, assign: Ast.Assign) !ControlFlow {
    const left_typ = try checker.checkExprMut(assign.left);
    const typ = try checker.checkExpr(assign.expr);
    try checker.unify(assign.expr.location, left_typ, typ);
    return .cont;
}

fn checkExprMut(checker: *Checker, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .unary => |unary| return checker.checkUnaryMut(unary.*, expr.location),
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
        .infer_struc,
        => {
            const typ = try checker.checkExpr(expr);
            checker.failNotMut(expr.location);
            return typ;
        },
    }
}

fn checkUnaryMut(checker: *Checker, unary: Ast.Unary, location: Location) !Typ {
    switch (unary.kind) {
        .deref => return checker.checkDeref(unary.expr, location, true),
        .notb, .ptr, .mut_ptr => {
            const typ = try checker.checkUnary(unary, location);
            checker.failNotMut(location);
            return typ;
        },
    }
}

fn checkUnary(checker: *Checker, unary: Ast.Unary, location: Location) !Typ {
    switch (unary.kind) {
        .deref => return checker.checkDeref(unary.expr, location, false),
        .notb => return checker.checkNotb(unary.expr),
        .ptr => return checker.checkPtr(unary.expr, false),
        .mut_ptr => return checker.checkPtr(unary.expr, true),
    }
}

fn checkDeref(checker: *Checker, expr: Ast.Expr, location: Location, mutable: bool) !Typ {
    const typ = try checker.checkExpr(expr);
    const norm = typ.normalise();
    switch (norm) {
        .ptr => |inner| {
            if (mutable) {
                checker.failNotMut(location);
            }
            return inner.*;
        },
        .mut_ptr => |inner| {
            return inner.*;
        },
        .err => return .err,
        .prime, .name, .any, .int, .array => {
            checker.fail(location, "cannot dereference type `{f}`", .{typ});
            return .err;
        },
        .lazy => unreachable,
    }
}

fn failNotMut(checker: *Checker, location: Location) void {
    checker.fail(location, "it is immutable", .{});
}

fn checkElem(checker: *Checker, elem: Ast.Elem, location: Location, mutable: bool) !Typ {
    const typ = try checker.checkExprWith(elem.expr, mutable);
    const index = try checker.checkExpr(elem.index);
    try checker.unify(elem.index.location, .int, index);
    const norm = typ.normalise();
    switch (norm) {
        .array => |array| return array.typ.*,
        .err => return .err,
        .prime, .name, .ptr, .any, .int, .mut_ptr => {
            checker.fail(location, "type `{f}` does not support indexing", .{typ});
            return .err;
        },
        .lazy => unreachable,
    }
}

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) !void {
    if (try canUnify(a, b, true)) {
        return;
    }
    checker.failWrongTyp(location, a, b);
    if (a == .ptr and a.ptr.* == .prime and a.ptr.*.prime == .u8 and b == .name and std.mem.eql(u8, b.name, "str")) {
        std.log.info("append `.ptr` to get C-style string\n", .{});
    }
}

fn failWrongTyp(checker: *Checker, location: Location, a: Typ, b: Typ) void {
    checker.fail(location,
        \\wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ a, b });
}

fn canUnify(a: Typ, b: Typ, active: bool) !bool {
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
        const res = try canUnify(a, b.lazy.*, active);
        if (res) {
            if (active) {
                b.lazy.* = a;
            }
        }
        return res;
    }
    if (@intFromEnum(a) != @intFromEnum(b)) {
        return false;
    }
    switch (a) {
        .prime => |aprime| return aprime == b.prime,
        .name => |aname| return std.mem.eql(u8, aname, b.name),
        // a == b <=> &a == &b due to memo
        .ptr => |aptr| return aptr == b.ptr or try canUnify(aptr.*, b.ptr.*, active),
        // a == b <=> &a == &b due to memo
        .mut_ptr => |aptr| return aptr == b.mut_ptr or try canUnify(aptr.*, b.mut_ptr.*, active),
        .array => |arr| {
            if (std.mem.eql(u8, arr.len, b.array.len)) {
                // a == b <=> &a == &b due to memo
                return arr.typ == b.array.typ or try canUnify(arr.typ.*, b.array.typ.*, active);
            }
            return false;
        },
        .lazy, .int, .any, .err => unreachable,
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
        const decl_typ = try checker.typs.makeTyp(typ_decl);
        try checker.unify(declare.expr.location, decl_typ, expr_typ);
        // if expr_typ is `<any>`
        typ = decl_typ;
    }
    if (checker.vars.get(declare.name)) |prev| {
        checker.failAlreadyDeclared(location, "item", declare.name, prev.location);
        return .cont;
    }
    try checker.vars_stack.append(checker.gpa, declare.name);
    try checker.vars.put(declare.name, .{
        .typ = typ,
        .location = location,
        .mutable = mutable,
        .can_be_mutable = true,
    });
    return .cont;
}

fn checkExpr(checker: *Checker, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .unary => |unary| return checker.checkUnary(unary.*, expr.location),
        .infer_struc => |struc| return checker.checkInferStruc(struc, expr.location),
        .int => |int| return checker.checkInt(expr.location, int),
        .str => return .{ .name = "str" },
        .vari => |name| return checker.checkVar(expr.location, name, false),
        .char => return .{ .prime = .u8 },
        .bool => return .{ .prime = .bool },
        .undef => |undef| return checker.checkUndef(undef, expr.location),
        .call => |call| return checker.checkCall(call, expr.location),
        .binary => |binary| return checker.checkBinary(binary.*),
        .field => |field| return checker.checkField(field.*, expr.location, false),
        .struc => |struc| return checker.checkStruc(struc, expr.location),
        .elem => |elem| return checker.checkElem(elem.*, expr.location, false),
    }
}

fn checkNotb(checker: *Checker, expr: Ast.Expr) !Typ {
    const typ = try checker.checkExpr(expr);
    try checker.unify(expr.location, .int, typ);
    return typ;
}

fn checkPtr(checker: *Checker, expr: Ast.Expr, mutable: bool) !Typ {
    const inner = try checker.checkExprWith(expr, mutable);
    const typ = try checker.typs.box(inner);
    if (mutable) {
        return .{ .mut_ptr = typ };
    }
    return .{ .ptr = typ };
}

fn checkInferStruc(checker: *Checker, struc: Ast.InferStruct, location: Location) !Typ {
    const typs = try checker.fun_arena.allocator().alloc(Typ, struc.fields.len);
    for (struc.fields, typs) |field, *typ| {
        typ.* = try checker.checkExpr(field.expr);
    }
    const lazy = try checker.typs.makeLazy();
    checker.lazies[struc.typ_id] = .{
        .location = location,
        .typ = lazy,
    };
    try checker.lazy_strucs.append(checker.gpa, .{
        .typ = lazy,
        .fields = struc.fields,
        .typs = typs,
        .location = location,
    });
    return .{ .lazy = lazy };
}

fn checkStruc(checker: *Checker, struc: Ast.StructExpr, location: Location) !Typ {
    const typs = try checker.gpa.alloc(Typ, struc.fields.len);
    defer checker.gpa.free(typs);
    for (struc.fields, typs) |field, *typ| {
        typ.* = try checker.checkExpr(field.expr);
    }
    try checker.checkStrucNow(location, struc, typs);
    return .{ .name = struc.name };
}

fn checkStrucNow(
    checker: *Checker,
    location: Location,
    struc: Ast.StructExpr,
    typs: []const Typ,
) !void {
    const decl = checker.structs.get(struc.name) orelse {
        checker.failNotStruct(location, .{ .name = struc.name });
        return;
    };
    for (struc.fields, typs) |field, typ| {
        const f_decl = decl.fields.get(field.name) orelse {
            checker.failNoField(field.location, field.name, struc.name);
            continue;
        };
        try checker.unify(field.expr.location, f_decl.typ, typ);
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
            checker.fail(location, "field `{s}` is not initialized", .{field_decl.*});
        }
    }
}

fn checkUndef(checker: *Checker, undef: Ast.Undef, location: Location) !Typ {
    const lazy = try checker.typs.makeLazy();
    checker.lazies[undef.typ_id] = .{
        .location = location,
        .typ = lazy,
    };
    return .{ .lazy = lazy };
}

fn checkInt(checker: *Checker, location: Location, int: []const u8) Typ {
    _ = std.fmt.parseInt(u64, int, 10) catch {
        checker.fail(location, "integer is too large", .{});
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
    const norm = expr_typ.normalise();
    if (norm == .err) {
        return .err;
    }
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
    checker.fail(location, "no field `{s}` in struct `{s}`", .{ field, struc });
}

fn failNotStruct(checker: *Checker, location: Location, typ: Typ) void {
    if (typ == .lazy and typ.lazy.* == .any) {
        checker.failShouldKnowTyp(location);
        typ.lazy.* = .err;
        return;
    }
    checker.fail(location, "type `{f}` is not a struct", .{typ});
}

fn failShouldKnowTyp(checker: *Checker, location: Location) void {
    checker.fail(location, "type should be known here", .{});
}

fn checkBinary(checker: *Checker, binary: Ast.Binary) !Typ {
    var left = try checker.checkExpr(binary.left);
    if (!left.isNumber()) {
        checker.failWrongTyp(binary.left.location, .int, left);
        left = .err;
    }
    const right = try checker.checkExpr(binary.right);
    try checker.unify(binary.right.location, left, right);
    switch (binary.kind) {
        .equ, .les => return .{ .prime = .bool },
        else => return left,
    }
}

fn checkVar(checker: *Checker, location: Location, name: []const u8, mutable: bool) Typ {
    const vari = checker.vars.getPtr(name) orelse {
        checker.fail(location, "item `{s}` is not declared", .{name});
        return .err;
    };
    vari.used = true;
    if (mutable) {
        if (vari.mutable) {
            vari.mutated = true;
        } else {
            checker.failNotMut(location);
            if (vari.can_be_mutable) {
                std.log.info("add `mut` before name in {f}\n", .{vari.location});
            }
        }
    }
    return vari.typ;
}

fn checkCall(checker: *Checker, call: Ast.Call, location: Location) !Typ {
    const header = checker.headers.getPtr(call.name) orelse {
        checker.fail(location, "item `{s}` is not declared", .{call.name});
        for (call.args) |arg| {
            _ = try checker.checkExpr(arg);
        }
        return .err;
    };
    header.used = true;
    for (call.args, header.params) |arg, param| {
        const typ = try checker.checkExpr(arg);
        try checker.unify(arg.location, param, typ);
    }
    return header.ret_typ;
}

fn checkRet(checker: *Checker, ret: Ast.Return, location: Location) !ControlFlow {
    if (ret.expr) |expr| {
        const typ = try checker.checkExpr(expr);
        try checker.unify(expr.location, checker.ret_typ, typ);
    } else if (checker.ret_typ != .prime or checker.ret_typ.prime != .void) {
        checker.fail(location, "should return a value", .{});
    }
    return .ret;
}

fn deinit(checker: *Checker) void {
    var structs = checker.structs.valueIterator();
    while (structs.next()) |struc| {
        struc.fields.deinit();
    }
    checker.structs.deinit();
    checker.vars.deinit();
    checker.headers.deinit();
    checker.lazy_strucs.deinit(checker.gpa);
    checker.typs.deinit();
    checker.fun_arena.deinit();
    checker.vars_stack.deinit(checker.gpa);
    checker.* = undefined;
}

fn fail(checker: *Checker, location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    checker.errors_cnt += 1;
}
