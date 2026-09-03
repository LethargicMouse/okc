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
const ExprInfo = struct {
    typ: Typ,
    mutable: bool,
};

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
    generics: []const []const u8,
    fields: std.StringHashMap(Field),
};

const Var = struct {
    typ: Typ,
    can_be_mutable: bool,
    mutable: bool,
    mutated: bool = false,
    used: bool = false,
};

const Header = struct {
    generics: []const []const u8,
    params: []const Typ,
    ret_typ: Typ,
    used: bool = false,
    is_extern: bool,
};

const Item = struct {
    const Kind = union(enum) {
        fun: Header,
        vari: Var,
        struc: Struct,

        fn describe(kind: Kind) []const u8 {
            return switch (kind) {
                .fun => "function",
                .vari => "variable",
                .struc => "struct",
            };
        }
    };
    kind: Kind,
    location: Location,
};

const Checker = @This();

gpa: std.mem.Allocator,
typs: Typs,
fun_arena: std.heap.ArenaAllocator,
vars_stack: std.ArrayList([]const u8) = .empty,
items: std.StringHashMap(Item),
llvm_typs: *LlvmTyps,
info: Info,
ret_typ: Typ = undefined,
errors_cnt: u16 = 0,
loops_nested: u16 = 0,

pub fn init(
    gpa: std.mem.Allocator,
    llvm_typs: *LlvmTyps,
    ast_info: Ast.Info,
) !Checker {
    return .{
        .gpa = gpa,
        .llvm_typs = llvm_typs,
        .fun_arena = .init(gpa),
        .typs = .init(gpa),
        .info = try .init(llvm_typs, ast_info),
        .items = .init(gpa),
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
    try checker.regSliceStruct();
    for (ast.items) |item| {
        try checker.regItem(item);
    }
    for (ast.items) |item| {
        try checker.checkItem(item);
    }
    checker.checkMain(ast.location);
    checker.checkItems();
}

fn convertTyp(checker: *Checker, typ: Typ, location: ?Location) !?LlvmTyp {
    return checker.convertTypRec(typ) catch |err| switch (err) {
        error.BadConvert => return null,
        error.ConvertAny => {
            if (location) |loc| {
                checker.failCannotInfer(typ, loc);
            }
            return null;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn convertTypRec(checker: Checker, typ: Typ) !LlvmTyp {
    switch (typ) {
        .name => |name| {
            const generics =
                try checker.llvm_typs.arena.allocator().alloc(LlvmTyp, name.generics.len);
            for (generics, name.generics) |*target, generic| {
                target.* = try checker.convertTypRec(generic);
            }
            return .{ .name = .{
                .name = name.name,
                .generics = generics,
            } };
        },
        .slice => |slice| return checker.convertTypRec(.{ .name = .{
            .name = "[]",
            .generics = &.{slice.typ.*},
        } }),
        .prime => |prime| return LlvmTyp.fromPrime(prime),
        .ptr => |ptr| {
            const inner = try checker.convertTypRec(ptr.typ.*);
            const new = try checker.llvm_typs.box(inner);
            return .{ .ptr = new };
        },
        .array => |array| {
            const inner = try checker.convertTypRec(array.typ.*);
            const new = try checker.llvm_typs.box(inner);
            return .{ .array = .{
                .len = array.len,
                .typ = new,
            } };
        },
        .err => return error.BadConvert,
        .any => {
            return error.ConvertAny;
        },
        .lazy => |inner| return checker.convertTypRec(inner.*),
    }
}

fn checkItems(checker: *Checker) void {
    var iter = checker.items.valueIterator();
    while (iter.next()) |item| {
        switch (item.kind) {
            .fun => |header| checker.checkHeaderUsage(header, item.location),
            .vari => unreachable,
            .struc => {},
        }
    }
}

fn checkHeaderUsage(checker: *Checker, header: Header, location: Location) void {
    if (!header.used) {
        checker.failUnused(location);
    }
}

fn regItem(checker: *Checker, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => |ext_fun| try checker.regHeader(ext_fun.header, true),
        .struc => |struc| try checker.regStruct(struc),
        .fun => |fun| try checker.regHeader(fun.header, false),
    }
}

fn checkItem(checker: *Checker, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => {},
        .struc => {},
        .fun => |fun| try checker.checkFun(fun),
    }
}

fn checkVarUsage(checker: *Checker, vari: Var, location: Location) void {
    if (!vari.used) {
        checker.failUnused(location);
    } else if (vari.mutable and !vari.mutated) {
        checker.fail(location, "variable is never mutated", .{});
        std.log.info("remove `mut` before name\n", .{});
    }
}

fn failUnused(checker: *Checker, location: Location) void {
    checker.fail(location, "item is never used", .{});
}

fn checkMain(checker: *Checker, location: Location) void {
    const item = checker.items.getPtr("main") orelse {
        checker.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        checker.fail(item.location, "item `main` is not a function", .{});
    }
    item.kind.fun.used = true;
}

fn regHeader(checker: *Checker, header: Ast.Header, is_extern: bool) !void {
    if (checker.items.get(header.name)) |prev| {
        checker.failAlreadyDeclared(header.location, header.name, prev.location);
        return;
    }
    const params = try checker.typs.arena.allocator().alloc(Typ, header.params.len);
    for (header.params, 0..) |param, i| {
        params[i] = try checker.typs.makeTyp(param.typ);
    }
    const ret_typ = try checker.typs.makeTyp(header.ret_typ);
    try checker.items.put(header.name, .{
        .location = header.location,
        .kind = .{ .fun = .{
            .generics = header.generics,
            .params = params,
            .ret_typ = ret_typ,
            .is_extern = is_extern,
        } },
    });
}

fn failAlreadyDeclared(
    checker: *Checker,
    location: Location,
    name: []const u8,
    prev: Location,
) void {
    checker.fail(
        location,
        "item `{s}` is already declared in {f}",
        .{ name, prev },
    );
}

fn regStruct(checker: *Checker, struc: Ast.Struct) !void {
    if (checker.items.get(struc.name)) |prev| {
        checker.failAlreadyDeclared(struc.location, struc.name, prev.location);
        return;
    }
    var res = Struct{
        .generics = struc.generics,
        .fields = .init(checker.gpa),
    };
    for (struc.fields) |field| {
        if (res.fields.get(field.name)) |prev| {
            checker.failAlreadyDeclared(field.location, field.name, prev.location);
            continue;
        }
        const typ = try checker.typs.makeTyp(field.typ);
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = typ,
        });
    }
    try checker.items.put(struc.name, .{
        .kind = .{ .struc = res },
        .location = struc.location,
    });
}

fn regSliceStruct(checker: *Checker) !void {
    try checker.regStruct(builtin.slice_struct);
}

fn checkFun(checker: *Checker, fun: Ast.Fun) !void {
    checker.ret_typ = checker.items.get(fun.header.name).?.kind.fun.ret_typ;
    const rbp = checker.vars_stack.items.len;
    for (fun.header.params) |param| {
        if (checker.items.get(param.name)) |prev| {
            checker.failAlreadyDeclared(param.location, param.name, prev.location);
            continue;
        }
        try checker.vars_stack.append(checker.gpa, param.name);
        try checker.items.put(param.name, .{
            .location = param.location,
            .kind = .{ .vari = .{
                .typ = try checker.typs.makeTyp(param.typ),
                .mutable = false,
                .can_be_mutable = false,
            } },
        });
    }
    const cf = try checker.checkBlock(fun.body);
    if (cf != .ret and !fun.header.ret_typ.isVoid()) {
        checker.fail(fun.header.location, "function may not return", .{});
    }
    checker.freeVars(rbp);
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
    checker.freeVars(rbp);
    return res;
}

fn freeVars(checker: *Checker, rbp: usize) void {
    for (checker.vars_stack.items[rbp..]) |name| {
        const kv = checker.items.fetchRemove(name).?.value;
        checker.checkVarUsage(kv.kind.vari, kv.location);
    }
    checker.vars_stack.shrinkRetainingCapacity(rbp);
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
    const info = try checker.checkExpr(ignore.expr, .any);
    if (info.typ == .prime and info.typ.prime == .void) {
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
    // no type hints to disallow `undefined;`
    const info = try checker.checkExpr(expr, .any);
    try checker.unify(expr.location, .{ .prime = .void }, info.typ);
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
    const info = try checker.checkExpr(branch.condition, .any);
    try checker.unify(branch.condition.location, .{ .prime = .bool }, info.typ);
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
    const left = try checker.checkExpr(op_assign.left, .any);
    if (!left.mutable) {
        checker.failNotMut(op_assign.left.location);
    }
    std.debug.assert(op_assign.kind.getClass() == .arith);
    if (!left.typ.isNumber()) {
        checker.failWrongTyp(op_assign.left.location, .named("<int>"), left.typ);
    }
    const right = try checker.checkExpr(op_assign.right, .any);
    try checker.unify(op_assign.right.location, left.typ, right.typ);
    return .cont;
}

fn checkAssign(checker: *Checker, assign: Ast.Assign) !ControlFlow {
    const left = try checker.checkExpr(assign.left, .any);
    if (left.mutable) {
        checker.markMutated(assign.left);
    } else {
        checker.failNotMut(assign.left.location);
    }
    const info = try checker.checkExpr(assign.expr, left.typ);
    try checker.unify(assign.expr.location, left.typ, info.typ);
    return .cont;
}

fn markMutated(checker: *Checker, expr: Ast.Expr) void {
    switch (expr.kind) {
        .vari => |name| checker.markVarMutated(name),
        else => {},
    }
}

fn markVarMutated(checker: *Checker, name: []const u8) void {
    if (checker.items.getPtr(name)) |item| {
        if (item.kind == .vari) {
            item.kind.vari.mutated = true;
        }
    }
    // not failing on absence cuz already failed in `checkVar`
}

fn checkUnary(checker: *Checker, unary: Ast.Unary, location: Location) !ExprInfo {
    switch (unary.kind) {
        .deref => return checker.checkDeref(unary.expr, location),
        .notb => return checker.checkNotb(unary.expr),
        .ptr => return checker.checkPtr(unary.expr),
        .mut_ptr => return checker.checkMutPtr(unary.expr),
    }
}

fn checkDeref(checker: *Checker, expr: Ast.Expr, location: Location) !ExprInfo {
    const info = try checker.checkExpr(expr, .any);
    const norm = info.typ.normalise();
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    switch (norm) {
        .ptr => |ptr| {
            return .{
                .typ = ptr.typ.*,
                .mutable = ptr.mutable,
            };
        },
        .err => return err,
        .prime, .name, .any, .array, .slice => {
            checker.fail(location, "cannot dereference type `{f}`", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}

fn failNotMut(checker: *Checker, location: Location) void {
    checker.fail(location, "it is immutable", .{});
}

fn checkElem(checker: *Checker, elem: Ast.Elem, location: Location) !ExprInfo {
    const info = try checker.checkExpr(elem.expr, .any);
    const index = try checker.checkExpr(elem.index, .{ .prime = .u64 });
    if (!index.typ.isNumber()) {
        checker.failWrongTyp(elem.index.location, .named("<int>"), index.typ);
    }
    const norm = info.typ.normalise();
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    switch (norm) {
        .array => |array| return .{
            .typ = array.typ.*,
            .mutable = info.mutable,
        },
        .slice => |slice| return .{
            .typ = slice.typ.*,
            .mutable = slice.mutable,
        },
        .err => return err,
        .prime, .name, .ptr, .any => {
            checker.fail(location, "type `{f}` does not support indexing", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) !void {
    if (try canUnify(a, b, true)) {
        return;
    }
    checker.failWrongTyp(location, a, b);
    if (a == .ptr and
        a.ptr.typ.* == .prime and
        a.ptr.typ.prime == .u8 and
        b == .slice and
        b.slice.typ.* == .prime and
        b.slice.typ.prime == .u8)
    {
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
    if (a == .lazy) {
        const res = try canUnify(a.lazy.*, b, active);
        if (res and active) {
            a.lazy.* = b;
        }
        return res;
    }
    if (b == .lazy) {
        const res = try canUnify(a, b.lazy.*, active);
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
        .name => |aname| {
            if (!std.mem.eql(u8, aname.name, b.name.name)) {
                return false;
            }
            for (aname.generics, b.name.generics) |ag, bg| {
                if (!try canUnify(ag, bg, active)) {
                    return false;
                }
            }
            return true;
        },
        .slice => |aslice| return aslice.mutable == b.slice.mutable and
            (aslice.typ == b.slice.typ or try canUnify(aslice.typ.*, b.slice.typ.*, active)),
        .ptr => |aptr| return aptr.mutable == b.ptr.mutable and
            (aptr.typ == b.ptr.typ or try canUnify(aptr.typ.*, b.ptr.typ.*, active)),
        .array => |arr| {
            if (std.mem.eql(u8, arr.len, b.array.len)) {
                return arr.typ == b.array.typ or try canUnify(arr.typ.*, b.array.typ.*, active);
            }
            return false;
        },
        .lazy, .any, .err => unreachable,
    }
}

fn checkDeclare(
    checker: *Checker,
    declare: Ast.Declare,
    location: Location,
    mutable: bool,
) !ControlFlow {
    var decl_typ: Typ = .any;
    if (declare.typ) |typ_decl| {
        decl_typ = try checker.typs.makeTyp(typ_decl);
    }
    var info = try checker.checkExpr(declare.expr, decl_typ);
    try checker.unify(declare.expr.location, decl_typ, info.typ);
    if (info.typ == .any) {
        info.typ = .err;
    }
    if (checker.items.get(declare.name)) |prev| {
        checker.failAlreadyDeclared(location, declare.name, prev.location);
        return .cont;
    }
    try checker.vars_stack.append(checker.gpa, declare.name);
    try checker.items.put(declare.name, .{
        .location = location,
        .kind = .{ .vari = .{
            .typ = info.typ,
            .mutable = mutable,
            .can_be_mutable = true,
        } },
    });
    return .cont;
}

fn checkExpr(checker: *Checker, expr: Ast.Expr, hint: Typ) Error!ExprInfo {
    switch (expr.kind) {
        .unary => |unary| return checker.checkUnary(unary.*, expr.location),
        .infer_struc => |struc| return checker.checkInferStruc(struc, expr.location, hint),
        .int => |int| return checker.checkInt(expr.location, int, hint),
        .str => return checker.checkStr(),
        .vari => |name| return checker.checkVar(expr.location, name),
        .char => return .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => return .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |undef| return checker.checkUndef(undef, expr.location, hint),
        .call => |call| return checker.checkCall(call, expr.location, hint),
        .binary => |binary| return checker.checkBinary(binary.*, hint),
        .field => |field| return checker.checkField(field.*, expr.location),
        .struc => |struc| return checker.checkStruc(struc, expr.location),
        .elem => |elem| return checker.checkElem(elem.*, expr.location),
    }
}

fn checkStr(checker: *Checker) !ExprInfo {
    const ptr = try checker.typs.box(.{ .prime = .u8 });
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .mutable = false,
        } },
        .mutable = false,
    };
}

fn checkNotb(checker: *Checker, expr: Ast.Expr) !ExprInfo {
    var info = try checker.checkExpr(expr, .any);
    if (!info.typ.isNumber()) {
        checker.failWrongTyp(expr.location, .named("<int>"), info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}

fn checkPtr(checker: *Checker, expr: Ast.Expr) !ExprInfo {
    const info = try checker.checkExpr(expr, .any);
    const ptr = try checker.typs.box(info.typ);
    return .{
        .typ = .{ .ptr = .{
            .typ = ptr,
            .mutable = false,
        } },
        .mutable = false,
    };
}

fn checkMutPtr(checker: *Checker, expr: Ast.Expr) !ExprInfo {
    const info = try checker.checkExpr(expr, .any);
    if (info.mutable) {
        checker.markMutated(expr);
    } else {
        checker.failNotMut(expr.location);
    }
    const typ = try checker.typs.box(info.typ);
    return .{
        .typ = .{ .ptr = .{
            .typ = typ,
            .mutable = true,
        } },
        .mutable = false,
    };
}

fn checkInferStruc(
    checker: *Checker,
    struc: Ast.InferStruct,
    location: Location,
    hint: Typ,
) Error!ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const name = switch (hint) {
        .name => |name| name,
        .slice => Typ.Name{
            .name = "[]",
            .generics = &.{.{ .prime = .u8 }},
        },
        .err => return err,
        .lazy => unreachable,
        .prime, .ptr, .any, .array => {
            checker.failCannotInfer(.any, location);
            for (struc.fields) |field| {
                _ = try checker.checkExpr(field.expr, .any);
            }
            return err;
        },
    };
    var info = try checker.checkTypedStruc(
        name,
        struc.fields,
        struc.struc_id,
        location,
    );
    if (std.mem.eql(u8, info.typ.name.name, "[]")) {
        const ptr = try checker.typs.box(info.typ.name.generics[0]);
        info.typ = .{ .slice = .{
            .typ = ptr,
            .mutable = hint.slice.mutable,
        } };
    }
    return info;
}

fn checkTypedStruc(
    checker: *Checker,
    name: Typ.Name,
    fields: []const Ast.NewField,
    struc_id: usize,
    location: Location,
) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const item = checker.items.get(name.name) orelse {
        checker.failNotDeclared(location, name.name);
        return err;
    };
    const decl = if (item.kind == .struc) item.kind.struc else {
        checker.failNotStruct(location, .{ .name = name });
        return err;
    };
    var resolver = checker.typs.makeResolver(checker.gpa);
    defer resolver.map.deinit();
    for (decl.generics, 0..) |generic, i| {
        if (name.generics.len != 0) {
            try resolver.map.put(generic, name.generics[i]);
        } else {
            const lazy = try checker.typs.makeLazy();
            try resolver.map.put(generic, .{ .lazy = lazy });
        }
    }
    for (fields) |field| {
        const f_decl = decl.fields.get(field.name) orelse {
            checker.failNoField(field.location, field.name, name.name);
            continue;
        };
        const decl_typ = try resolver.resolve(f_decl.typ);
        const info = try checker.checkExpr(field.expr, decl_typ);
        try checker.unify(field.expr.location, decl_typ, info.typ);
    }
    var iter = decl.fields.keyIterator();
    while (iter.next()) |field_decl| {
        var unused = true;
        for (fields) |field| {
            if (std.mem.eql(u8, field_decl.*, field.name)) {
                unused = false;
                break;
            }
        }
        if (unused) {
            checker.fail(location, "field `{s}` is not initialized", .{field_decl.*});
        }
    }
    var generics = name.generics;
    if (generics.len == 0) {
        const new_generics = try checker.typs.arena.allocator().alloc(Typ, decl.generics.len);
        for (new_generics, decl.generics) |*target, generic| {
            target.* = resolver.map.get(generic).?;
        }
        generics = new_generics;
    }
    const typ = Typ{ .name = .{
        .name = name.name,
        .generics = generics,
    } };
    if (try checker.convertTyp(typ, location)) |llvm_typ| {
        checker.info.strucs[struc_id] = llvm_typ.name;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkStruc(checker: *Checker, struc: Ast.StructExpr, location: Location) !ExprInfo {
    return checker.checkTypedStruc(
        .{ .name = struc.name },
        struc.fields,
        struc.struc_id,
        location,
    );
}

fn checkUndef(checker: *Checker, undef: Ast.Undef, location: Location, typ: Typ) !ExprInfo {
    if (try checker.convertTyp(typ, location)) |llvm_typ| {
        checker.info.typs[undef.typ_id] = llvm_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkInt(checker: *Checker, location: Location, int: Ast.Int, hint: Typ) !ExprInfo {
    _ = std.fmt.parseInt(u64, int.str, 10) catch {
        checker.fail(location, "integer is too large", .{});
    };
    const typ = if (hint.isNumber()) hint else {
        checker.failCannotInfer(.any, location);
        return .{
            .typ = .err,
            .mutable = false,
        };
    };
    if (try checker.convertTyp(typ, location)) |llvm_typ| {
        checker.info.typs[int.typ_id] = llvm_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkField(checker: *Checker, field: Ast.Field, location: Location) !ExprInfo {
    var info = try checker.checkExpr(field.expr, .any);
    const norm = info.typ.normalise();
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    if (norm == .err) {
        return err;
    }
    var name: Typ.Name = undefined;
    switch (norm) {
        .name => |n| name = n,
        // auto-deref
        .ptr => |ptr| if (ptr.typ.* == .name) {
            name = ptr.typ.name;
            info.mutable = ptr.mutable;
        } else {
            checker.failNotStruct(field.expr.location, info.typ);
            return err;
        },
        .slice => |inner| name = .{
            .name = "[]",
            .generics = &.{inner.typ.*},
        },
        else => {
            checker.failNotStruct(field.expr.location, info.typ);
            return err;
        },
    }
    const item = checker.items.get(name.name) orelse {
        checker.failNotStruct(field.expr.location, info.typ);
        return err;
    };
    const struc = if (item.kind == .struc) item.kind.struc else {
        checker.failNotStruct(field.expr.location, info.typ);
        return err;
    };
    const fiel = struc.fields.get(field.name) orelse {
        checker.failNoField(location, field.name, name.name);
        return err;
    };
    var resolver = checker.typs.makeResolver(checker.gpa);
    defer resolver.map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolver.map.put(generic, typ);
    }
    const typ = try resolver.resolve(fiel.typ);
    if (try checker.convertTyp(typ, location)) |llvm_typ| {
        checker.info.typs[field.typ_id] = llvm_typ;
    }
    return .{
        .typ = typ,
        .mutable = info.mutable,
    };
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
    checker.fail(location, "type `{f}` is not a struct", .{typ});
}

fn failCannotInfer(checker: *Checker, typ: Typ, location: Location) void {
    checker.fail(location, "cannot infer type", .{});
    if (typ != .any) {
        std.log.info("best guess is `{f}`\n", .{typ});
    }
}

fn checkBinary(checker: *Checker, binary: Ast.Binary, hint: Typ) !ExprInfo {
    const inner_hint = switch (binary.kind.getClass()) {
        .arith => hint,
        .bool => .any,
    };
    var left = try checker.checkExpr(binary.left, inner_hint);
    if (!left.typ.isNumber()) {
        checker.failWrongTyp(binary.left.location, .named("<int>"), left.typ);
        left.typ = .err;
    }
    const right = try checker.checkExpr(binary.right, left.typ);
    try checker.unify(binary.right.location, left.typ, right.typ);
    const typ = switch (binary.kind.getClass()) {
        .arith => left.typ,
        .bool => Typ{ .prime = .bool },
    };
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkVar(checker: *Checker, location: Location, name: []const u8) ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    const item = checker.items.getPtr(name) orelse {
        checker.failNotDeclared(location, name);
        return err;
    };
    const vari = switch (item.kind) {
        .fun => {
            checker.fail(location, "function pointers currently not supported", .{});
            return err;
        },
        .struc => {
            checker.fail(location, "it is a type", .{});
            return err;
        },
        .vari => |*vari| vari,
    };
    vari.used = true;
    return .{
        .typ = vari.typ,
        .mutable = vari.mutable,
    };
}

fn failNotDeclared(checker: *Checker, location: Location, name: []const u8) void {
    checker.fail(location, "item `{s}` is not declared", .{name});
}

fn checkCall(checker: *Checker, call: Ast.Call, location: Location, hint: Typ) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const item = checker.items.getPtr(call.name) orelse {
        checker.failNotDeclared(location, call.name);
        for (call.args) |arg| {
            _ = try checker.checkExpr(arg, .any);
        }
        return err;
    };
    const header = switch (item.kind) {
        .vari => {
            checker.fail(location, "function pointers currently not supported", .{});
            return err;
        },
        .struc => {
            checker.fail(location, "expected function, found type", .{});
            return err;
        },
        .fun => |*header| header,
    };
    header.used = true;
    var resolver = checker.typs.makeResolver(checker.gpa);
    defer resolver.map.deinit();
    for (header.generics) |generic| {
        const ptr = try checker.typs.makeLazy();
        try resolver.map.put(generic, .{ .lazy = ptr });
    }
    const ret_typ = try resolver.resolve(header.ret_typ);
    // to propagate hint to generics
    _ = try canUnify(ret_typ, hint, true);
    for (call.args, header.params) |arg, param| {
        const param_typ = try resolver.resolve(param);
        const info = try checker.checkExpr(arg, param_typ.normalise());
        try checker.unify(arg.location, param_typ, info.typ);
    }
    const generics = try checker.llvm_typs.arena.allocator().alloc(LlvmTyp, header.generics.len);
    for (generics, header.generics) |*target, generic| {
        if (try checker.convertTyp(resolver.map.get(generic).?, null)) |llvm_typ| {
            target.* = llvm_typ;
        }
    }
    if (header.is_extern) {
        checker.info.calls[call.call_id].generics = &.{};
    } else {
        checker.info.calls[call.call_id].generics = generics;
    }
    if (try checker.convertTyp(ret_typ, location)) |llvm_typ| {
        checker.info.calls[call.call_id].ret_typ = llvm_typ;
    }
    return .{
        .typ = ret_typ,
        .mutable = false,
    };
}

fn checkRet(checker: *Checker, ret: Ast.Return, location: Location) !ControlFlow {
    if (ret.expr) |expr| {
        const info = try checker.checkExpr(expr, checker.ret_typ);
        try checker.unify(expr.location, checker.ret_typ, info.typ);
    } else if (checker.ret_typ != .prime or checker.ret_typ.prime != .void) {
        checker.fail(location, "should return a value", .{});
    }
    return .ret;
}

fn deinit(checker: *Checker) void {
    var items = checker.items.valueIterator();
    while (items.next()) |item| {
        switch (item.kind) {
            .struc => |*struc| struc.fields.deinit(),
            .fun => {},
            .vari => {},
        }
    }
    checker.items.deinit();
    checker.typs.deinit();
    checker.fun_arena.deinit();
    checker.vars_stack.deinit(checker.gpa);
    checker.* = undefined;
}

fn fail(checker: *Checker, location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    checker.errors_cnt += 1;
}
