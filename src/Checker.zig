const std = @import("std");

const Ast = @import("Ast.zig");
const Location = @import("Location.zig");
const Memo = @import("memo.zig").Memo;
const Resolver = @import("resolver.zig").Resolver(Typ);
const Typ = @import("typ.zig").Typ;

const Error = error{OutOfMemory};

const ConvertReq = struct {
    to: *Ast.Typ,
    from: *Typ,
    location: Location,
};

const ExprHint = struct {
    typ: Typ = .any,
    mutable: bool = false,
};

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
    defaulted: bool,
    used: bool = false,
};

const Struct = struct {
    generics: []const Ast.Generic,
    fields: std.StringHashMap(Field),

    fn deinit(struc: *Struct) void {
        struc.fields.deinit();
        struc.* = undefined;
    }
};

const Var = struct {
    typ: Typ,
    can_be_mutable: bool,
    mutable: bool,
    mutated: bool = false,
};

const Header = struct {
    generics: []const Ast.Generic,
    params: []const Typ,
    ret_typ: Typ,
};

const Item = struct {
    const Kind = union(enum) {
        fun: Header,
        vari: Var,
        struc: Struct,
    };
    kind: Kind,
    location: Location,
    used: bool = false,

    fn deinit(item: *Item) void {
        switch (item.kind) {
            .struc => |*struc| struc.deinit(),
            .fun => {},
            .vari => {},
        }
    }
};

const Checker = @This();

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
typ_memo: Memo(Typ),
ast_typ_memo: *Memo(Ast.Typ),
fun_arena: std.heap.ArenaAllocator,
vars_stack: std.ArrayList([]const u8) = .empty,
ast_items: std.StringHashMap(*const Ast.Item),
items: std.StringHashMap(Item),
ret_typ: Typ = undefined,
errors_cnt: u16 = 0,
loops_nested: u16 = 0,
current_generics: []const Ast.Generic = &.{},
generics_usage: std.DynamicBitSetUnmanaged,
convert_queue: std.ArrayList(ConvertReq) = .empty,

pub fn init(
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    ast_typ_memo: *Memo(Ast.Typ),
) !Checker {
    return .{
        .gpa = gpa,
        .arena = arena,
        .ast_typ_memo = ast_typ_memo,
        .fun_arena = .init(gpa),
        .typ_memo = .init(arena),
        .ast_items = .init(gpa),
        .items = .init(gpa),
        .generics_usage = try .initEmpty(gpa, 0),
    };
}

pub fn run(checker: *Checker, ast: Ast) !std.StringHashMap(*const Ast.Item) {
    defer checker.deinit();
    errdefer checker.ast_items.deinit();
    try checker.checkAst(ast);
    if (checker.errors_cnt != 0) {
        std.log.err("check failed with {} errors", .{checker.errors_cnt});
        return error.Handled;
    }
    return checker.ast_items;
}

fn checkAst(checker: *Checker, ast: Ast) !void {
    for (ast.items) |*item| {
        try checker.ast_items.put(item.getName(), item);
        try checker.regItem(item);
    }
    for (ast.items) |item| {
        try checker.checkItem(item);
    }
    checker.checkMain(ast.location);
    checker.checkItems();
}

fn convertTyp(checker: *Checker, typ: Typ, location: ?Location) !?Ast.Typ {
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

fn convertTypRec(checker: Checker, typ: Typ) !Ast.Typ {
    switch (typ) {
        .name => |name| {
            const generics =
                try checker.ast_typ_memo.arena.allocator().alloc(Ast.Typ, name.generics.len);
            for (generics, name.generics) |*target, generic| {
                target.* = try checker.convertTypRec(generic);
            }
            return .{ .name = .{
                .name = name.name,
                .generics = generics,
            } };
        },
        .fun => |fun| {
            const params = try checker.ast_typ_memo.arena.allocator().alloc(Ast.Typ, fun.params.len);
            for (params, fun.params) |*target, param| {
                target.* = try checker.convertTypRec(param);
            }
            const ret_typ = try checker.convertTypRec(fun.ret_typ.*);
            const ptr = try checker.ast_typ_memo.box(ret_typ);
            return .{ .fun = .{
                .params = params,
                .ret_typ = ptr,
            } };
        },
        .slice => |slice| {
            const new = try checker.convertTypRec(slice.typ.*);
            const ptr = try checker.ast_typ_memo.box(new);
            return .{ .slice = .{
                .typ = ptr,
                .mutable = slice.mutable,
            } };
        },
        .prime => |prime| return .{ .prime = prime },
        .ptr => |ptr| {
            const inner = try checker.convertTypRec(ptr.typ.*);
            const new = try checker.ast_typ_memo.box(inner);
            return .{ .ptr = .{
                .typ = new,
                .mutable = ptr.mutable,
            } };
        },
        .array => |array| {
            const inner = try checker.convertTypRec(array.typ.*);
            const new = try checker.ast_typ_memo.box(inner);
            return .{ .array = .{
                .len = array.len,
                .typ = new,
            } };
        },
        .err => return error.BadConvert,
        .any, .int => return error.ConvertAny,
        .lazy => |inner| return checker.convertTypRec(inner.*),
    }
}

fn checkItems(checker: *Checker) void {
    var iter = checker.items.valueIterator();
    while (iter.next()) |item| {
        checker.checkItemUsage(item.*);
    }
}

fn checkItemUsage(checker: *Checker, item: Item) void {
    if (item.used) {
        switch (item.kind) {
            .fun => {},
            .vari => |vari| checker.checkVarUsage(vari, item.location),
            .struc => |struc| checker.checkStructUsage(struc),
        }
    } else {
        checker.failUnused(item.location);
    }
}

fn checkStructUsage(checker: *Checker, struc: Struct) void {
    var iter = struc.fields.valueIterator();
    while (iter.next()) |field| {
        if (!field.used) {
            checker.failUnused(field.location);
        }
    }
}

fn regItem(checker: *Checker, item: *Ast.Item) !void {
    switch (item.kind) {
        .ext_fun => |ext_fun| try checker.regHeader(ext_fun.header, item.location),
        .struc => |struc| try checker.regStruct(struc, item.location),
        .fun => |fun| try checker.regHeader(fun.header, item.location),
        .constant => |*declare| try checker.regConst(declare, item.location),
    }
}

fn regConst(checker: *Checker, declare: *Ast.Declare, location: Location) !void {
    const hint_typ = if (declare.typ) |typ| try checker.checkTyp(typ) else .any;
    const typ = try checker.checkConstExpr(&declare.expr, .{ .typ = hint_typ });
    if (declare.typ) |typ_decl| {
        const decl_typ = try checker.checkTyp(typ_decl);
        _ = checker.unify(location, decl_typ, typ);
    }
    if (checker.items.get(declare.name)) |prev| {
        checker.failAlreadyDeclared(location, declare.name, prev.location);
        return;
    }
    try checker.items.put(declare.name, .{ .location = location, .kind = .{ .vari = .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    } } });
}

fn checkConstExpr(checker: *Checker, expr: *Ast.Expr, hint: ExprHint) !Typ {
    const info = try checker.checkExpr(expr, hint);
    checker.checkComptime(expr.*);
    return info.typ;
}

fn checkComptime(checker: *Checker, expr: Ast.Expr) void {
    switch (expr.kind) {
        .str => {},
        .array => |array| {
            for (array.exprs) |elem| {
                checker.checkComptime(elem);
            }
        },
        .named_struc => |struc| {
            for (struc.fields) |field| {
                checker.checkComptime(field.expr);
            }
        },
        .struc => |struc| {
            for (struc.fields) |field| {
                checker.checkComptime(field.expr);
            }
        },
        else => checker.fail(expr.location, "cannot evaluate at compile time", .{}),
    }
}

fn checkItem(checker: *Checker, item: Ast.Item) !void {
    switch (item.kind) {
        .ext_fun => {},
        .struc => {},
        .constant => {},
        .fun => |fun| try checker.checkFun(fun, item.location),
    }
}

fn checkVarUsage(checker: *Checker, vari: Var, location: Location) void {
    if (vari.mutable and !vari.mutated) {
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
    item.used = true;
}

fn regHeader(checker: *Checker, header: Ast.Header, location: Location) !void {
    checker.current_generics = header.generics;
    try checker.generics_usage.resize(checker.gpa, header.generics.len, false);
    if (checker.items.get(header.name)) |prev| {
        checker.failAlreadyDeclared(location, header.name, prev.location);
        return;
    }
    const params = try checker.arena.allocator().alloc(Typ, header.params.len);
    for (header.params, 0..) |param, i| {
        params[i] = try checker.checkTyp(param.typ);
    }
    const ret_typ = try checker.checkTyp(header.ret_typ);
    checker.checkGenericsUsage();
    try checker.items.put(header.name, .{
        .location = location,
        .kind = .{ .fun = .{
            .generics = header.generics,
            .params = params,
            .ret_typ = ret_typ,
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

fn regStruct(checker: *Checker, struc: Ast.Struct, location: Location) !void {
    if (checker.items.get(struc.name)) |prev| {
        checker.failAlreadyDeclared(location, struc.name, prev.location);
        return;
    }
    var res = Struct{
        .generics = struc.generics,
        .fields = .init(checker.gpa),
    };
    checker.current_generics = struc.generics;
    try checker.generics_usage.resize(checker.gpa, struc.generics.len, false);
    for (struc.fields) |*field| {
        if (res.fields.get(field.name)) |prev| {
            checker.failAlreadyDeclared(field.location, field.name, prev.location);
            continue;
        }
        const typ = try checker.checkTyp(field.typ);
        var defaulted = false;
        if (field.default) |*expr| {
            const expr_typ = try checker.checkConstExpr(expr, .{ .typ = typ });
            _ = checker.unify(expr.location, typ, expr_typ);
            defaulted = true;
        }
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = typ,
            .defaulted = defaulted,
            .used = field.name[0] == '_',
        });
    }
    checker.checkGenericsUsage();
    try checker.items.put(struc.name, .{
        .location = location,
        .kind = .{ .struc = res },
    });
}

fn checkGenericsUsage(checker: *Checker) void {
    for (checker.current_generics, 0..) |generic, i| {
        if (!checker.generics_usage.isSet(i)) {
            checker.failUnused(generic.location);
        }
    }
}

fn checkFun(checker: *Checker, fun: Ast.Fun, location: Location) !void {
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
                .typ = try checker.checkTyp(param.typ),
                .mutable = false,
                .can_be_mutable = false,
            } },
        });
    }
    const cf = try checker.checkBlock(fun.body);
    if (cf != .ret and !fun.header.ret_typ.isVoid()) {
        checker.fail(location, "function may not return", .{});
    }
    checker.freeVars(rbp);
    try checker.flushConvertQueue();
    _ = checker.fun_arena.reset(.retain_capacity);
}

fn flushConvertQueue(checker: *Checker) !void {
    for (checker.convert_queue.items) |req| {
        if (try checker.convertTyp(.{ .lazy = req.from }, req.location)) |ast_typ| {
            req.to.* = ast_typ;
        }
    }
    checker.convert_queue.clearRetainingCapacity();
}

fn checkBlock(checker: *Checker, block: []Ast.Statement) !ControlFlow {
    var res = ControlFlow.cont;
    const rbp = checker.vars_stack.items.len;
    for (block, 0..) |*statement, i| {
        const cf = try checker.checkStatement(statement);
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
        const item = checker.items.fetchRemove(name).?.value;
        checker.checkItemUsage(item);
    }
    checker.vars_stack.shrinkRetainingCapacity(rbp);
}

fn checkStatement(checker: *Checker, statement: *Ast.Statement) Error!ControlFlow {
    switch (statement.kind) {
        .unre => return .ret,
        .brek => return checker.checkBreak(statement.location),
        .ret => |*ret| return checker.checkRet(ret, statement.location),
        .expr => |*expr| return checker.checkExprStatement(expr),
        .declare => |*declare| {
            return checker.checkDeclare(declare, statement.location, false);
        },
        .op_assign => |*op_assign| return checker.checkOpAssign(op_assign),
        .assign => |*assign| return checker.checkAssign(assign),
        .iff => |*iff| return checker.checkIf(iff),
        .whi => |*whi| return checker.checkWhile(whi),
        .ignore => |*ignore| return checker.checkIgnore(ignore, statement.location),
        .mut_declare => |*declare| {
            return checker.checkDeclare(declare, statement.location, true);
        },
    }
}

fn checkIgnore(checker: *Checker, ignore: *Ast.Ignore, location: Location) !ControlFlow {
    const info = try checker.checkExpr(&ignore.expr, .{});
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

fn checkExprStatement(checker: *Checker, expr: *Ast.Expr) !ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try checker.checkExpr(expr, .{});
    _ = checker.unify(expr.location, .{ .prime = .void }, info.typ);
    return .cont;
}

fn checkWhile(checker: *Checker, whi: *Ast.While) !ControlFlow {
    const cf = try checker.checkBranch(&whi.branch, true);
    switch (cf) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}

fn checkIf(checker: *Checker, iff: *Ast.If) !ControlFlow {
    var res = try checker.checkBranch(&iff.branch, false);
    for (iff.else_ifs) |*branch| {
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

fn checkBranch(checker: *Checker, branch: *Ast.Branch, loop: bool) !ControlFlow {
    const info = try checker.checkExpr(&branch.condition, .{});
    _ = checker.unify(branch.condition.location, .{ .prime = .bool }, info.typ);
    if (loop) {
        checker.loops_nested += 1;
    }
    const cf = try checker.checkBlock(branch.body);
    if (loop) {
        checker.loops_nested -= 1;
    }
    return cf;
}

fn checkOpAssign(checker: *Checker, op_assign: *Ast.OpAssign) !ControlFlow {
    var left = try checker.checkExpr(&op_assign.left, .{ .mutable = true });
    if (!left.mutable) {
        checker.failNotMut(op_assign.left.location);
    }
    std.debug.assert(op_assign.kind.getClass() == .arith);
    if (!left.typ.isNumber()) {
        checker.failWrongTyp(op_assign.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try checker.checkExpr(&op_assign.right, .{});
    _ = checker.unify(op_assign.right.location, left.typ, right.typ);
    return .cont;
}

fn checkAssign(checker: *Checker, assign: *Ast.Assign) !ControlFlow {
    const left = try checker.checkExpr(&assign.left, .{ .mutable = true });
    if (!left.mutable) {
        checker.failNotMut(assign.left.location);
    }
    const info = try checker.checkExpr(&assign.expr, .{ .typ = left.typ });
    _ = checker.unify(assign.expr.location, left.typ, info.typ);
    return .cont;
}

fn checkUnary(checker: *Checker, unary: *Ast.Unary, location: Location, hint: Typ) !ExprInfo {
    switch (unary.kind) {
        .deref => return checker.checkDeref(&unary.expr, location),
        .notb => return checker.checkNotb(&unary.expr, hint),
        .ptr => return checker.checkPtr(&unary.expr, hint),
        .neg => return checker.checkNeg(&unary.expr, hint),
    }
}

fn checkNeg(checker: *Checker, expr: *Ast.Expr, hint: Typ) !ExprInfo {
    var info = try checker.checkExpr(expr, .{ .typ = hint });
    if (!info.typ.isNumber()) {
        checker.failWrongTyp(expr.location, .int, info.typ);
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}

fn checkDeref(checker: *Checker, expr: *Ast.Expr, location: Location) !ExprInfo {
    const info = try checker.checkExpr(expr, .{});
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
        .prime, .name, .any, .array, .slice, .fun, .int => {
            checker.fail(location, "cannot dereference type `{f}`", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}

fn failNotMut(checker: *Checker, location: Location) void {
    checker.fail(location, "it is immutable", .{});
}

fn checkElem(checker: *Checker, elem: *Ast.Elem, location: Location) !ExprInfo {
    const info = try checker.checkExpr(&elem.expr, .{});
    const index = try checker.checkExpr(&elem.index, .{ .typ = .{ .prime = .u64 } });
    _ = checker.unify(elem.index.location, .{ .prime = .u64 }, index.typ);
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
        .prime, .name, .ptr, .any, .fun, .int => {
            checker.fail(location, "type `{f}` does not support indexing", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}

const debug_unify = false;

fn unify(checker: *Checker, location: Location, a: Typ, b: Typ) Typ {
    if (canUnify(a, b, true)) |typ| {
        if (debug_unify) {
            std.debug.print("==> {f}\n", .{typ});
        }
        return typ;
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
    return .err;
}

fn failWrongTyp(checker: *Checker, location: Location, a: Typ, b: Typ) void {
    checker.fail(location,
        \\wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ a, b });
}

fn canUnify(a: Typ, b: Typ, active: bool) ?Typ {
    if (debug_unify) {
        std.debug.print("unify {f} vs {f}\n", .{ a, b });
    }
    if (a == .err or b == .err) {
        return .err;
    }
    if (a == .any) {
        return b;
    }
    if (b == .any) {
        return a;
    }
    if (a == .lazy and b == .lazy) {
        const sa = a.lazy.shorten();
        const sb = b.lazy.shorten();
        if (sa != sb) {
            const typ = canUnify(sa.*, sb.*, active) orelse return null;
            sa.setLazy(typ);
            sb.setLazy(.{ .lazy = sa });
        }
        return .{ .lazy = sa };
    }
    if (a == .lazy) {
        const res = canUnify(a.lazy.*, b, active) orelse return null;
        if (active) {
            a.lazy.setLazy(res);
        }
        return a;
    }
    if (b == .lazy) {
        const res = canUnify(a, b.lazy.*, active) orelse return null;
        if (active) {
            b.lazy.setLazy(res);
        }
        return b;
    }
    if (a == .slice and b == .ptr and b.ptr.typ.* == .array and
        a.slice.mutable == b.ptr.mutable)
    {
        if (a.slice.typ != b.ptr.typ.array.typ) {
            _ = canUnify(a.slice.typ.*, b.ptr.typ.array.typ.*, active) orelse return null;
        }
        return a;
    }
    if (a == .int and b.isNumber()) {
        return b;
    }
    if (b == .int and a.isNumber()) {
        return a;
    }
    if (@intFromEnum(a) != @intFromEnum(b)) {
        return null;
    }
    switch (a) {
        .prime => |aprime| if (aprime == b.prime) {
            return b;
        } else {
            return null;
        },
        .name => |aname| {
            if (!std.mem.eql(u8, aname.name, b.name.name)) {
                return null;
            }
            for (aname.generics, b.name.generics) |ag, bg| {
                _ = canUnify(ag, bg, active) orelse return null;
            }
            return b;
        },
        .fun => |fun| {
            if (fun.ret_typ != b.fun.ret_typ) {
                _ = canUnify(fun.ret_typ.*, b.fun.ret_typ.*, active) orelse return null;
            }
            for (fun.params, b.fun.params) |ap, bp| {
                _ = canUnify(ap, bp, active) orelse return null;
            }
            return a;
        },
        .slice => |aslice| {
            if (aslice.mutable != b.slice.mutable) {
                return null;
            }
            if (aslice.typ != b.slice.typ) {
                _ = canUnify(aslice.typ.*, b.slice.typ.*, active) orelse return null;
            }
            return a;
        },
        .ptr => |aptr| {
            if (aptr.mutable and !b.ptr.mutable) {
                return null;
            }
            if (aptr.typ != b.ptr.typ and canUnify(aptr.typ.*, b.ptr.typ.*, active) == null) {
                return null;
            }
            return a;
        },
        .array => |arr| {
            if (arr.len != b.array.len or
                (arr.typ != b.array.typ and canUnify(arr.typ.*, b.array.typ.*, active) == null))
            {
                return null;
            }
            return a;
        },
        .lazy, .any, .err, .int => unreachable,
    }
}

fn checkDeclare(
    checker: *Checker,
    declare: *Ast.Declare,
    location: Location,
    mutable: bool,
) !ControlFlow {
    var decl_typ: Typ = .any;
    if (declare.typ) |typ_decl| {
        decl_typ = try checker.checkTyp(typ_decl);
    }
    const info = try checker.checkExpr(&declare.expr, .{ .typ = decl_typ });
    const typ = checker.unify(declare.expr.location, decl_typ, info.typ);
    if (checker.items.get(declare.name)) |prev| {
        checker.failAlreadyDeclared(location, declare.name, prev.location);
        return .cont;
    }
    try checker.vars_stack.append(checker.gpa, declare.name);
    try checker.items.put(declare.name, .{
        .location = location,
        .kind = .{ .vari = .{
            .typ = typ,
            .mutable = mutable,
            .can_be_mutable = true,
        } },
    });
    return .cont;
}

fn checkExpr(checker: *Checker, expr: *Ast.Expr, hint: ExprHint) Error!ExprInfo {
    switch (expr.kind) {
        .sizeof => |typ| return checker.checkSizeof(typ),
        .array => |*array| return checker.checkArray(array, expr.location, hint.typ),
        .unary => |unary| return checker.checkUnary(unary, expr.location, hint.typ),
        .struc => |*struc| return checker.checkStructExpr(struc, expr.location, hint.typ),
        .int => |*int| return checker.checkInt(expr.location, int),
        .str => return checker.checkStr(),
        .vari => return checker.checkVar(expr, hint.mutable),
        .char => return .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => return .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |*undef| return checker.checkUndef(undef, expr.location, hint.typ),
        .call => |*call| return checker.checkCall(call, expr.location, hint.typ),
        .binary => |binary| return checker.checkBinary(binary),
        .field => |field| return checker.checkField(field, expr.location, hint.mutable),
        .named_struc => |*struc| return checker.checkNamedStructExpr(struc, expr.location),
        .elem => |elem| return checker.checkElem(elem, expr.location),
        .fn_ptr => unreachable,
    }
}

fn checkSizeof(checker: *Checker, typ: Ast.Typ) !ExprInfo {
    _ = try checker.checkTyp(typ);
    return .{
        .typ = .{ .prime = .u64 },
        .mutable = false,
    };
}

fn checkArray(checker: *Checker, array: *Ast.Array, location: Location, hint: Typ) !ExprInfo {
    var inner_typ: Typ = .any;
    var inner_hint = if (hint == .array) hint.array.typ.* else .any;
    if (array.mtyp) |typ| {
        inner_typ = try checker.checkTyp(typ);
        inner_hint = inner_typ;
    }
    if (array.exprs.len == 0) {
        const typ = Typ{ .array = .{
            .typ = try checker.typ_memo.box(inner_hint),
            .len = 0,
        } };
        if (try checker.convertTyp(typ, location)) |ast_typ| {
            array.typ = ast_typ;
        }
        return .{
            .typ = typ,
            .mutable = false,
        };
    }
    for (array.exprs) |*expr| {
        const info = try checker.checkExpr(expr, .{ .typ = inner_hint });
        inner_typ = checker.unify(expr.location, inner_typ, info.typ);
    }
    const typ = Typ{ .array = .{
        .typ = try checker.typ_memo.box(inner_typ),
        .len = array.exprs.len,
    } };
    if (try checker.convertTyp(typ, location)) |ast_typ| {
        array.typ = ast_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkStr(checker: *Checker) !ExprInfo {
    const ptr = try checker.typ_memo.box(.{ .prime = .u8 });
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .mutable = false,
        } },
        .mutable = false,
    };
}

fn checkNotb(checker: *Checker, expr: *Ast.Expr, hint: Typ) !ExprInfo {
    var info = try checker.checkExpr(expr, .{ .typ = hint });
    if (!info.typ.isNumber()) {
        checker.failWrongTyp(expr.location, .int, info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}

fn checkPtr(checker: *Checker, expr: *Ast.Expr, hint: Typ) !ExprInfo {
    const mutable = if (hint == .ptr) hint.ptr.mutable else false;
    const info = try checker.checkExpr(expr, .{ .mutable = mutable });
    const ptr = try checker.typ_memo.box(info.typ);
    return .{
        .typ = .{ .ptr = .{
            .typ = ptr,
            .mutable = info.mutable,
        } },
        .mutable = false,
    };
}

fn checkStructExpr(
    checker: *Checker,
    struc: *Ast.StructExpr,
    location: Location,
    hint: Typ,
) Error!ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const name = switch (hint) {
        .name => |name| name,
        .slice => |slice| return checker.checkSliceStruc(
            slice,
            struc.fields,
            &struc.typ,
            location,
        ),
        .err => return err,
        .lazy => unreachable,
        .prime, .ptr, .any, .array, .fun, .int => {
            checker.failCannotInfer(.any, location);
            for (struc.fields) |*field| {
                _ = try checker.checkExpr(&field.expr, .{});
            }
            return err;
        },
    };
    return checker.checkTypedStruc(
        name,
        struc.fields,
        &struc.typ,
        location,
    );
}

fn checkSliceStruc(
    checker: *Checker,
    slice: Typ.Slice,
    fields: []Ast.NewField,
    typ_target: *Ast.Typ,
    location: Location,
) !ExprInfo {
    var was_ptr: ?*const Typ = null;
    var was_len = false;
    for (fields) |*field| {
        if (std.mem.eql(u8, field.name, "ptr")) {
            if (was_ptr) |_| {
                checker.failNewFieldSecond(field.location, field.name);
            }
            const expected = Typ{ .ptr = .{
                .typ = slice.typ,
                .mutable = slice.mutable,
            } };
            const info = try checker.checkExpr(&field.expr, .{ .typ = expected });
            const typ = checker.unify(field.expr.location, expected, info.typ);
            was_ptr = if (typ == .ptr) typ.ptr.typ else try checker.typ_memo.box(.err);
        } else if (std.mem.eql(u8, field.name, "len")) {
            if (was_len) {
                checker.failNewFieldSecond(field.location, field.name);
            }
            const info = try checker.checkExpr(&field.expr, .{ .typ = .{ .prime = .u64 } });
            _ = checker.unify(field.expr.location, .{ .prime = .u64 }, info.typ);
            was_len = true;
        }
    }
    if (!was_len) {
        checker.failNotInit(location, "len");
    }
    if (was_ptr == null) {
        checker.failNotInit(location, "ptr");
    }
    const typ = Typ{ .slice = .{
        .typ = was_ptr.?,
        .mutable = slice.mutable,
    } };
    if (try checker.convertTyp(typ, location)) |ast_typ| {
        typ_target.* = ast_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn failNewFieldSecond(checker: *Checker, location: Location, name: []const u8) void {
    checker.fail(location, "field `{s}` initialized second time", .{name});
}

fn checkTypedStruc(
    checker: *Checker,
    name: Typ.Name,
    fields: []Ast.NewField,
    typ_target: *Ast.Typ,
    location: Location,
) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const item = checker.items.getPtr(name.name) orelse {
        checker.failNotDeclared(location, name.name);
        return err;
    };
    item.used = true;
    const decl = if (item.kind == .struc) item.kind.struc else {
        checker.failNotStruct(location, .{ .name = name });
        return err;
    };
    var generics = name.generics;
    if (generics.len == 0) {
        generics = try checker.makeGenerics(decl.generics.len);
    }
    var resolver = Resolver.init(checker.gpa, &checker.typ_memo);
    defer resolver.map.deinit();
    for (decl.generics, generics) |generic, typ| {
        try resolver.map.put(generic.name, typ);
    }
    for (fields) |*field| {
        try checker.checkNewField(field, name.name, decl.fields, &resolver);
    }
    checker.checkFieldsInitialised(decl.fields, fields, location);
    const typ = Typ{ .name = .{
        .name = name.name,
        .generics = generics,
    } };
    if (try checker.convertTyp(typ, location)) |ast_typ| {
        typ_target.* = ast_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn makeGenerics(checker: *Checker, len: usize) ![]const Typ {
    const res = try checker.arena.allocator().alloc(Typ, len);
    for (res) |*target| {
        const lazy = try checker.fun_arena.allocator().create(Typ);
        lazy.* = .any;
        target.* = .{ .lazy = lazy };
    }
    return res;
}

fn checkFieldsInitialised(
    checker: *Checker,
    decl_fields: std.StringHashMap(Field),
    fields: []const Ast.NewField,
    location: Location,
) void {
    var iter = decl_fields.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.defaulted) {
            continue;
        }
        var unused = true;
        for (fields) |field| {
            if (std.mem.eql(u8, entry.key_ptr.*, field.name)) {
                unused = false;
                break;
            }
        }
        if (unused) {
            checker.failNotInit(location, entry.key_ptr.*);
        }
    }
}

fn checkNewField(
    checker: *Checker,
    field: *Ast.NewField,
    struc_name: []const u8,
    decl_fields: std.StringHashMap(Field),
    resolver: *Resolver,
) !void {
    const f_decl = decl_fields.get(field.name) orelse {
        checker.failNoField(field.location, field.name, struc_name);
        return;
    };
    const decl_typ = try f_decl.typ.resolve(resolver);
    const info = try checker.checkExpr(&field.expr, .{ .typ = decl_typ });
    _ = checker.unify(field.expr.location, decl_typ, info.typ);
}

fn failNotInit(checker: *Checker, location: Location, name: []const u8) void {
    checker.fail(location, "field `{s}` is not initialized", .{name});
}

fn checkNamedStructExpr(checker: *Checker, struc: *Ast.NamedStructExpr, location: Location) !ExprInfo {
    return checker.checkTypedStruc(
        .{ .name = struc.name },
        struc.fields,
        &struc.typ,
        location,
    );
}

fn checkUndef(checker: *Checker, undef: *Ast.Undef, location: Location, typ: Typ) !ExprInfo {
    if (try checker.convertTyp(typ, location)) |ast_typ| {
        undef.typ = ast_typ;
    }
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkInt(checker: *Checker, location: Location, int: *Ast.Int) !ExprInfo {
    const ptr = try checker.fun_arena.allocator().create(Typ);
    ptr.* = .int;
    try checker.convert_queue.append(checker.gpa, .{
        .from = ptr,
        .to = &int.typ,
        .location = location,
    });
    return .{
        .typ = .{ .lazy = ptr },
        .mutable = false,
    };
}

fn checkField(
    checker: *Checker,
    field: *Ast.Field,
    location: Location,
    hint_mutable: bool,
) !ExprInfo {
    var info = try checker.checkExpr(&field.expr, .{ .mutable = hint_mutable });
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    var norm = info.typ.normalise();
    if (norm == .ptr) {
        info.mutable = norm.ptr.mutable;
        norm = norm.ptr.typ.normalise();
    }
    if (norm == .slice) {
        return checker.checkSliceField(
            norm.slice,
            info.mutable,
            field.name,
            &field.typ,
            location,
        );
    }
    const name = checker.getTypName(norm, field.expr.location) orelse return err;
    const item = checker.items.get(name.name) orelse {
        checker.failNotStruct(field.expr.location, norm);
        return err;
    };
    const struc = if (item.kind == .struc) item.kind.struc else {
        checker.failNotStruct(field.expr.location, norm);
        return err;
    };
    const fiel = struc.fields.getPtr(field.name) orelse {
        checker.failNoField(location, field.name, name.name);
        return err;
    };
    fiel.used = true;
    var resolver = Resolver.init(checker.gpa, &checker.typ_memo);
    defer resolver.map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolver.map.put(generic.name, typ);
    }
    const typ = try fiel.typ.resolve(&resolver);
    if (try checker.convertTyp(typ, location)) |ast_typ| {
        field.typ = ast_typ;
    }
    return .{
        .typ = typ,
        .mutable = info.mutable,
    };
}

fn checkSliceField(
    checker: *Checker,
    slice: Typ.Slice,
    mutable: bool,
    name: []const u8,
    typ_target: *Ast.Typ,
    location: Location,
) !ExprInfo {
    if (std.mem.eql(u8, name, "ptr")) {
        const typ = Typ{ .ptr = .{
            .typ = slice.typ,
            .mutable = slice.mutable,
        } };
        if (try checker.convertTyp(typ, location)) |ast_typ| {
            typ_target.* = ast_typ;
        }
        return .{
            .typ = typ,
            .mutable = mutable,
        };
    }
    if (std.mem.eql(u8, name, "len")) {
        typ_target.* = .{ .prime = .u64 };
        return .{
            .typ = .{ .prime = .u64 },
            .mutable = mutable,
        };
    }
    return .{
        .typ = .err,
        .mutable = true,
    };
}

fn getTypName(checker: *Checker, norm: Typ, location: Location) ?Typ.Name {
    switch (norm) {
        .err => return null,
        .name => |name| return name,
        .slice, .array, .any, .lazy, .int => {
            std.log.err("getTypName: {f}", .{norm});
            unreachable;
        },
        .fun, .prime, .ptr => {
            checker.failNotStruct(location, norm);
            return null;
        },
    }
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

fn checkBinary(checker: *Checker, binary: *Ast.Binary) !ExprInfo {
    var left = try checker.checkExpr(&binary.left, .{});
    if (!left.typ.isNumber()) {
        checker.failWrongTyp(binary.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try checker.checkExpr(&binary.right, .{});
    const unityp = checker.unify(binary.right.location, left.typ, right.typ);
    const typ = switch (binary.kind.getClass()) {
        .arith => unityp,
        .bool => Typ{ .prime = .bool },
    };
    return .{
        .typ = typ,
        .mutable = false,
    };
}

fn checkVar(
    checker: *Checker,
    expr: *Ast.Expr,
    hint_mutable: bool,
) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    const name = expr.kind.vari;
    const item = checker.items.getPtr(name) orelse {
        checker.failNotDeclared(expr.location, name);
        return err;
    };
    switch (item.kind) {
        .fun => |header| {
            item.used = true;
            expr.kind = .{ .fn_ptr = name };
            return .{
                .typ = .{ .fun = .{
                    .params = header.params,
                    .ret_typ = try checker.typ_memo.box(header.ret_typ),
                } },
                .mutable = false,
            };
        },
        .struc => {
            checker.fail(expr.location, "it is a type", .{});
            return err;
        },
        .vari => |*vari| {
            item.used = true;
            if (hint_mutable) {
                if (vari.mutable) {
                    vari.mutated = true;
                } else {
                    if (vari.can_be_mutable) {
                        std.log.info("add `mut` before name in {f}", .{item.location});
                    }
                }
            }
            return .{
                .typ = vari.typ,
                .mutable = vari.mutable,
            };
        },
    }
}

fn failNotDeclared(checker: *Checker, location: Location, name: []const u8) void {
    checker.fail(location, "item `{s}` is not declared", .{name});
}

fn checkCall(checker: *Checker, call: *Ast.Call, location: Location, hint: Typ) !ExprInfo {
    const header = checker.getHeader(call.name, location) orelse {
        for (call.args) |*arg| {
            _ = try checker.checkExpr(arg, .{});
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    };
    var resolver = Resolver.init(checker.gpa, &checker.typ_memo);
    defer resolver.map.deinit();
    for (header.generics) |generic| {
        const ptr = try checker.fun_arena.allocator().create(Typ);
        ptr.* = .any;
        try resolver.map.put(generic.name, .{ .lazy = ptr });
    }
    const ret_typ = try header.ret_typ.resolve(&resolver);
    // to propagate hint to generics
    _ = canUnify(ret_typ, hint, true);
    for (call.args, header.params) |*arg, param| {
        const param_typ = try param.resolve(&resolver);
        const info = try checker.checkExpr(arg, .{ .typ = param_typ.normalise() });
        _ = checker.unify(arg.location, param_typ, info.typ);
    }
    call.generics = try checker.ast_typ_memo.arena.allocator().alloc(Ast.Typ, header.generics.len);
    for (call.generics, header.generics) |*target, generic| {
        if (try checker.convertTyp(resolver.map.get(generic.name).?, null)) |llvm_typ| {
            target.* = llvm_typ;
        }
    }
    if (try checker.convertTyp(ret_typ, location)) |ast_typ| {
        call.ret_typ = ast_typ;
    }
    return .{
        .typ = ret_typ,
        .mutable = false,
    };
}

fn getHeader(checker: *Checker, name: []const u8, location: Location) ?Header {
    const item = checker.items.getPtr(name) orelse {
        checker.failNotDeclared(location, name);
        return null;
    };
    switch (item.kind) {
        .vari => |vari| switch (vari.typ) {
            .fun => |fun| {
                item.used = true;
                return Header{
                    .generics = &.{},
                    .params = fun.params,
                    .ret_typ = fun.ret_typ.*,
                };
            },
            else => {
                checker.fail(location, "value of type `{}` is not a function", .{vari.typ});
                return null;
            },
        },
        .struc => {
            checker.fail(location, "expected function, found type", .{});
            return null;
        },
        .fun => |header| {
            item.used = true;
            return header;
        },
    }
}

fn checkRet(checker: *Checker, ret: *Ast.Return, location: Location) !ControlFlow {
    if (ret.expr) |*expr| {
        const info = try checker.checkExpr(expr, .{ .typ = checker.ret_typ });
        _ = checker.unify(expr.location, checker.ret_typ, info.typ);
    } else if (checker.ret_typ != .prime or checker.ret_typ.prime != .void) {
        checker.fail(location, "should return a value", .{});
    }
    return .ret;
}

fn deinit(checker: *Checker) void {
    checker.deinitItems();
    checker.typ_memo.deinit();
    checker.fun_arena.deinit();
    checker.vars_stack.deinit(checker.gpa);
    checker.generics_usage.deinit(checker.gpa);
    checker.convert_queue.deinit(checker.gpa);
    checker.* = undefined;
}

fn deinitItems(checker: *Checker) void {
    var items = checker.items.valueIterator();
    while (items.next()) |item| {
        item.deinit();
    }
    checker.items.deinit();
}

fn fail(checker: *Checker, location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    checker.errors_cnt += 1;
}

pub fn checkTypDecl(checker: *Checker, name: Ast.Typ.Name) void {
    const item = checker.items.getPtr(name.name) orelse {
        checker.fail(name.location, "item `{s}` is not declared", .{name.name});
        return;
    };
    switch (item.kind) {
        .fun, .vari => {
            checker.fail(name.location, "`{s}` is not a type", .{name.name});
        },
        .struc => |struc| {
            item.used = true;
            if (struc.generics.len != name.generics.len) {
                checker.fail(
                    name.location,
                    "expected {} generics\n        found {}",
                    .{ struc.generics.len, name.generics.len },
                );
            }
        },
    }
}

pub fn checkTyp(checker: *Checker, typ: Ast.Typ) !Typ {
    switch (typ) {
        .slice => |inner| {
            const new = try checker.checkTyp(inner.typ.*);
            const ptr = try checker.typ_memo.box(new);
            return .{ .slice = .{
                .typ = ptr,
                .mutable = inner.mutable,
            } };
        },
        .fun => |fun| {
            const params = try checker.arena.allocator().alloc(Typ, fun.params.len);
            for (params, fun.params) |*target, param| {
                target.* = try checker.checkTyp(param);
            }
            const ret_typ = try checker.checkTyp(fun.ret_typ.*);
            const ptr = try checker.typ_memo.box(ret_typ);
            return .{ .fun = .{
                .params = params,
                .ret_typ = ptr,
            } };
        },
        .prime => |prime| return .{ .prime = prime },
        .name => |name| {
            var check_decl = true;
            for (checker.current_generics, 0..) |generic, i| {
                if (std.mem.eql(u8, generic.name, name.name)) {
                    check_decl = false;
                    checker.generics_usage.set(i);
                    break;
                }
            }
            if (check_decl) {
                checker.checkTypDecl(name);
            }
            const generics = try checker.arena.allocator().alloc(Typ, name.generics.len);
            for (generics, name.generics) |*target, generic| {
                target.* = try checker.checkTyp(generic);
            }
            return .{ .name = .{
                .name = name.name,
                .generics = generics,
            } };
        },
        .ptr => |inner| {
            const inner_typ = try checker.checkTyp(inner.typ.*);
            const ptr = try checker.typ_memo.box(inner_typ);
            return .{ .ptr = .{
                .typ = ptr,
                .mutable = inner.mutable,
            } };
        },
        .array => |array| {
            const inner_typ = try checker.checkTyp(array.typ.*);
            const ptr = try checker.typ_memo.box(inner_typ);
            return .{ .array = .{
                .len = array.len,
                .typ = ptr,
            } };
        },
    }
}
