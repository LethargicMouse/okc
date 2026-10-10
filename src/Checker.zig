const std = @import("std");

const ast = @import("ast/mod.zig");
const HashMap = @import("hash_map.zig").HashMap;
const Location = @import("Location.zig");
const memo = @import("memo.zig");
const Typ = @import("typ/mod.zig").Typ;
const Failer = @import("Failer.zig");

const Self = @This();
gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
typ_mem: *memo.Memo(Typ),
fun_arena: std.heap.ArenaAllocator,
vars_stack: std.ArrayList([]const u8) = .empty,
items: std.StringHashMap(Item),
ret_typ: Typ = undefined,
failer: *Failer,
loops_nested: u16 = 0,
current_generics: []const ast.Item.Generic = &.{},
generics_usage: std.DynamicBitSetUnmanaged,
solve_queue: std.ArrayList(SolveRequest) = .empty,

pub fn init(
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    typ_mem: *memo.Memo(Typ),
    failer: *Failer,
) error{OutOfMemory}!Self {
    return .{
        .gpa = gpa,
        .arena = arena,
        .failer = failer,
        .typ_mem = typ_mem,
        .fun_arena = .init(gpa),
        .items = .init(gpa),
        .generics_usage = try .initEmpty(gpa, 0),
    };
}

pub fn run(self: *Self, module: ast.Module) error{ OutOfMemory, Handled }!void {
    defer self.deinit();
    try self.checkModule(module);
    try self.failer.ensureNoErrors();
    return;
}

fn checkModule(self: *Self, module: ast.Module) !void {
    for (module.items) |*item| {
        try self.regItem(item);
    }
    for (module.items) |item| {
        try self.checkItem(item);
    }
    self.checkMain(module.location);
    self.checkItemsUsage();
}

const ConvertError = error{ BadConvert, ConvertAny, OutOfMemory };

fn checkItemsUsage(self: *Self) void {
    var iter = self.items.iterator();
    while (iter.next()) |entry| {
        self.checkItemUsage(entry.key_ptr.*, entry.value_ptr.*);
    }
}

fn checkItemUsage(self: *Self, name: []const u8, item: Item) void {
    if (item.used) {
        switch (item.kind) {
            .fun, .typ => {},
            .vari => |vari| self.checkVarUsage(vari, item.location),
            .struc => |struc| self.checkStructUsage(struc),
        }
    } else {
        self.failer.unused(item.location, name);
    }
}

fn checkStructUsage(self: *Self, struc: Struct) void {
    var iter = struc.fields.iterator();
    while (iter.next()) |entry| {
        if (!entry.value_ptr.used) {
            self.failer.unused(entry.value_ptr.location, entry.key_ptr.*);
        }
    }
}

fn regItem(self: *Self, item: *ast.Item) !void {
    const kind: Item.Kind = switch (item.kind) {
        .typ_alias => |alias| .{ .typ = alias.typ },
        .ext_fun => |*ext_fun| .{ .fun = &ext_fun.header },
        .struc => |struc| try self.regStruct(struc),
        .fun => |*fun| .{ .fun = &fun.header },
        .constant => |*declare| try self.regConst(declare),
        .use => unreachable,
    };
    if (kind == .fun) {
        try self.checkHeader(kind.fun);
    }
    if (self.items.get(item.name)) |prev| {
        self.failer.alreadyDeclared(item.location, item.name, prev.location);
        return;
    }
    try self.items.put(item.name, .{
        .location = item.location,
        .kind = kind,
    });
}

fn regConst(self: *Self, declare: *ast.Stmt.Declare) !Item.Kind {
    const hint_typ = if (declare.typ) |typ| typ else .any;
    const typ = try self.checkConstExpr(&declare.expr, .{ .typ = hint_typ });
    if (declare.typ) |typ_decl| {
        _ = self.unify(declare.expr.location, typ_decl, typ);
    }
    return .{ .vari = .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    } };
}

fn checkConstExpr(self: *Self, expr: *ast.Expr, hint: ExprHint) !Typ {
    const info = try self.checkExpr(expr, hint);
    self.checkExprComptime(expr.*);
    return info.typ;
}

fn checkExprComptime(self: *Self, expr: ast.Expr) void {
    switch (expr.kind) {
        .str, .bool, .char, .int, .sizeof, .vari, .undef => {},
        .call, .method => self.failer.fail(expr.location, "cannot evaluate at compile time", .{}),
        .field => |field| self.checkExprComptime(field.expr),
        .unary => |unary| self.checkExprComptime(unary.expr),
        .elem => |elem| self.checkElemComptime(elem.*),
        .binary => |binary| self.checkBinaryComptime(binary.*),
        .subslice => |subslice| self.checkSubsliceComptime(subslice.*),
        .array => |array| self.checkArrayComptime(array),
        .named_struc => |named| self.checkStructExprComptime(named.struc),
        .struc => |struc| self.checkStructExprComptime(struc),
    }
}

fn checkElemComptime(self: *Self, elem: ast.Expr.Elem) void {
    self.checkExprComptime(elem.expr);
    self.checkExprComptime(elem.index);
}

fn checkBinaryComptime(self: *Self, binary: ast.Expr.Binary) void {
    self.checkExprComptime(binary.left);
    self.checkExprComptime(binary.right);
}

fn checkSubsliceComptime(self: *Self, subslice: ast.Expr.Subslice) void {
    self.checkExprComptime(subslice.expr);
    self.checkExprComptime(subslice.start);
    self.checkExprComptime(subslice.end);
}

fn checkStructExprComptime(self: *Self, struc: ast.Expr.Struct) void {
    for (struc.fields) |field| {
        self.checkExprComptime(field.expr);
    }
}

fn checkArrayComptime(self: *Self, array: ast.Expr.Array) void {
    for (array.exprs) |elem| {
        self.checkExprComptime(elem);
    }
}

fn checkItem(self: *Self, item: ast.Item) error{OutOfMemory}!void {
    switch (item.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try self.checkFun(fun, item.location),
        .use => unreachable,
    }
}

fn checkHeader(self: *Self, header: *ast.Item.Fun.Header) !void {
    self.current_generics = header.generics;
    try self.generics_usage.resize(self.gpa, header.generics.len, false);
    for (header.params) |*param| {
        param.typ = try self.checkTyp(param.typ);
    }
    header.ret_typ = try self.checkTyp(header.ret_typ);
    self.checkGenericsUsage();
}

fn checkTyp(self: *Self, typ: Typ) error{OutOfMemory}!Typ {
    return switch (typ) {
        .array => |array| .{ .array = try self.checkArrayTyp(array) },
        .slice => |slice| .{ .slice = try self.checkSliceTyp(slice) },
        .fun => |fun| .{ .fun = try self.checkFunTyp(fun) },
        .loc_name => |located| self.checkLocNameTyp(located),
        .ptr => |ptr| .{ .ptr = try self.checkPtrTyp(ptr) },
        .prime, .any, .err, .int, .name, .lazy => typ,
    };
}

fn checkFunTyp(self: *Self, fun: Typ.Fun) !Typ.Fun {
    const params = try self.typ_mem.alloc(fun.params.len);
    for (params, fun.params) |*target, param| {
        target.* = try self.checkTyp(param);
    }
    const new = try self.checkTyp(fun.ret_typ.*);
    return .{
        .params = try self.typ_mem.save(params),
        .ret_typ = try self.typ_mem.box(new),
    };
}

fn checkArrayTyp(self: *Self, array: Typ.Array) !Typ.Array {
    const new = try self.checkTyp(array.typ.*);
    return .{
        .typ = try self.typ_mem.box(new),
        .len = array.len,
    };
}

fn checkSliceTyp(self: *Self, slice: Typ.Slice) !Typ.Slice {
    const new = try self.checkTyp(slice.typ.*);
    return .{
        .typ = try self.typ_mem.box(new),
        .mutable = slice.mutable,
    };
}

fn checkPtrTyp(self: *Self, ptr: Typ.Ptr) !Typ.Ptr {
    const new = try self.checkTyp(ptr.typ.*);
    return .{
        .typ = try self.typ_mem.box(new),
        .mutable = ptr.mutable,
    };
}

fn checkLocNameTyp(self: *Self, located: Typ.Name.Located) !Typ {
    const loc_name: Typ.Name.Located = .{
        .location = located.location,
        .name = try self.checkNameTyp(located.name),
    };
    for (self.current_generics, 0..) |generic, i| {
        if (std.mem.eql(u8, generic.name, located.name.name)) {
            self.generics_usage.set(i);
            return .{ .loc_name = loc_name };
        }
    }
    const maybe_resolved = self.checkTypDecl(loc_name) catch |err| switch (err) {
        error.BadType => return .err,
    };
    if (maybe_resolved) |resolved| {
        return resolved;
    }
    return .{ .loc_name = loc_name };
}

fn checkNameTyp(self: *Self, name: Typ.Name) !Typ.Name {
    const generics = try self.typ_mem.alloc(name.generics.len);
    defer self.typ_mem.free(generics);
    for (generics, name.generics) |*target, generic| {
        target.* = try self.checkTyp(generic);
    }
    return .{
        .name = name.name,
        .generics = try self.typ_mem.save(generics),
    };
}

fn checkVarUsage(self: *Self, vari: Var, location: Location) void {
    if (vari.mutable and !vari.mutated) {
        self.failer.fail(location, "variable is never mutated", .{});
        std.log.info("remove `mut` before name\n", .{});
    }
}

fn checkMain(self: *Self, location: Location) void {
    const item = self.items.getPtr("main") orelse {
        self.failer.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        self.failer.fail(item.location, "item `main` is not a function", .{});
    }
    item.used = true;
}

fn regStruct(self: *Self, struc: ast.Item.Struct) !Item.Kind {
    try self.checkGenericsRedeclare(struc.generics);
    var res = Struct{
        .generics = struc.generics,
        .fields = .init(self.gpa),
    };
    for (struc.fields) |*field| {
        var defaulted = false;
        if (field.default) |*expr| {
            const expr_typ = try self.checkConstExpr(expr, .{ .typ = field.typ });
            _ = self.unify(expr.location, field.typ, expr_typ);
            defaulted = true;
        }
        if (res.fields.get(field.name)) |prev| {
            self.failer.alreadyDeclared(field.location, field.name, prev.location);
            continue;
        }
        try res.fields.put(field.name, .{
            .location = field.location,
            .typ = field.typ,
            .defaulted = defaulted,
            .used = field.name[0] == '_',
        });
    }
    return .{ .struc = res };
}

fn checkGenericsRedeclare(self: *Self, generics: []const ast.Item.Generic) !void {
    var map = std.StringHashMap(Location).init(self.gpa);
    defer map.deinit();
    for (generics) |generic| {
        if (self.items.get(generic.name)) |prev| {
            self.failer.alreadyDeclared(generic.location, generic.name, prev.location);
        }
        const entry = try map.getOrPut(generic.name);
        if (entry.found_existing) {
            self.failer.alreadyDeclared(generic.location, generic.name, entry.value_ptr.*);
        } else {
            entry.value_ptr.* = generic.location;
        }
    }
}

fn checkGenericsUsage(self: *Self) void {
    for (self.current_generics, 0..) |generic, i| {
        if (!self.generics_usage.isSet(i)) {
            self.failer.unused(generic.location, generic.name);
        }
    }
}

fn checkFun(self: *Self, fun: ast.Item.Fun, location: Location) !void {
    self.ret_typ = fun.header.ret_typ;
    const rbp = self.vars_stack.items.len;
    for (fun.header.params) |param| {
        try self.declareVar(param.name, .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        }, param.location);
    }
    const cf = try self.checkBlock(fun.body);
    if (cf != .ret and !fun.header.ret_typ.isVoid()) {
        self.failer.fail(location, "function may not return", .{});
    }
    self.freeVars(rbp);
    for (self.solve_queue.items) |req| {
        req.typ.* = try self.solveTyp(req.typ.*);
    }
    self.solve_queue.clearRetainingCapacity();
    _ = self.fun_arena.reset(.retain_capacity);
}

fn solveTyp(self: Self, typ: Typ) error{OutOfMemory}!Typ {
    switch (typ) {
        .array => |array| {
            const new = try self.solveTyp(array.typ.*);
            return .{ .array = .{
                .typ = try self.typ_mem.box(new),
                .len = array.len,
            } };
        },
        .fun => |fun| {
            const params = try self.typ_mem.alloc(fun.params.len);
            defer self.typ_mem.free(params);
            for (params, fun.params) |*target, param| {
                target.* = try self.solveTyp(param);
            }
            const new = try self.solveTyp(fun.ret_typ.*);
            return .{ .fun = .{
                .params = try self.typ_mem.save(params),
                .ret_typ = try self.typ_mem.box(new),
            } };
        },
        .name => |name| return .{ .name = try self.solveNameTyp(name) },
        .loc_name => |located| return .{ .loc_name = .{
            .location = located.location,
            .name = try self.solveNameTyp(located.name),
        } },
        .ptr => |ptr| {
            const new = try self.solveTyp(ptr.typ.*);
            return .{ .ptr = .{
                .typ = try self.typ_mem.box(new),
                .mutable = ptr.mutable,
            } };
        },
        .slice => |slice| {
            const new = try self.solveTyp(slice.typ.*);
            return .{ .slice = .{
                .typ = try self.typ_mem.box(new),
                .mutable = false,
            } };
        },
        .lazy => |inner| return try self.solveTyp(inner.*),
        .any, .err, .prime, .int => return typ,
    }
}

fn solveNameTyp(self: Self, name: Typ.Name) !Typ.Name {
    const generics = try self.typ_mem.alloc(name.generics.len);
    defer self.typ_mem.free(generics);
    for (generics, name.generics) |*target, generic| {
        target.* = try self.solveTyp(generic);
    }
    return .{
        .generics = try self.typ_mem.save(generics),
        .name = name.name,
    };
}

fn checkLoopBlock(self: *Self, block: []ast.Stmt) !ControlFlow {
    self.loops_nested += 1;
    const res = try self.checkBlock(block);
    self.loops_nested -= 1;
    switch (res) {
        .ret => return .ret,
        .brek, .cont => return .cont,
    }
}

fn checkBlock(self: *Self, block: []ast.Stmt) !ControlFlow {
    var res = ControlFlow.cont;
    const rbp = self.vars_stack.items.len;
    for (block, 0..) |*stmt, i| {
        const cf = try self.checkStmt(stmt);
        if (cf != .cont) {
            if (res == .cont) {
                res = cf;
            }
            if (i + 1 != block.len) {
                self.failer.fail(block[i + 1].location, "Stmt is unreachable", .{});
            }
        }
    }
    self.freeVars(rbp);
    return res;
}

fn freeVars(self: *Self, rbp: usize) void {
    for (self.vars_stack.items[rbp..]) |name| {
        self.freeVar(name);
    }
    self.vars_stack.shrinkRetainingCapacity(rbp);
}

fn checkStmt(self: *Self, stmt: *ast.Stmt) error{OutOfMemory}!ControlFlow {
    switch (stmt.kind) {
        .for_range => |*forr| return self.checkForRange(forr),
        .forr => |*forr| return self.checkFor(forr),
        .unre => return .ret,
        .brek => return self.checkBreak(stmt.location),
        .ret => |*ret| return self.checkRet(ret, stmt.location),
        .expr => |*expr| return self.checkExprStmt(expr),
        .declare => |*named| return self.checkDeclare(named.name, &named.declare, stmt.location),
        .op_assign => |*op_assign| return self.checkOpAssign(op_assign),
        .assign => |*assign| return self.checkAssign(assign),
        .iff => |*iff| return self.checkIf(iff),
        .whi => |*whi| return self.checkWhile(whi),
        .ignore => |*ignore| return self.checkIgnore(ignore, stmt.location),
    }
}

fn checkForRange(self: *Self, forr: *ast.Stmt.ForRange) !ControlFlow {
    var start = try self.checkExpr(&forr.start, .{});
    if (!start.typ.isNumber()) {
        self.failer.wrongTyp(forr.start.location, .int, start.typ);
        start.typ = .err;
    }
    const end = try self.checkExpr(&forr.end, .{});
    const typ = self.unify(forr.end.location, start.typ, end.typ);
    try self.declareVar(forr.vari, .{
        .typ = typ,
        .mutable = false,
        .can_be_mutable = false,
    }, forr.vari_location);
    defer {
        _ = self.vars_stack.pop();
        self.freeVar(forr.vari);
    }
    return self.checkLoopBlock(forr.body);
}

fn checkFor(self: *Self, forr: *ast.Stmt.For) !ControlFlow {
    const info = try self.checkExpr(&forr.expr, .{});
    const elem_info = self.getElemExprInfo(info, forr.expr.location) orelse ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    try self.declareVar(forr.vari, .{
        .typ = elem_info.typ,
        .mutable = false,
        .can_be_mutable = false,
    }, forr.vari_location);
    defer {
        _ = self.vars_stack.pop();
        self.freeVar(forr.vari);
    }
    return self.checkLoopBlock(forr.body);
}

fn freeVar(self: *Self, name: []const u8) void {
    const item = self.items.fetchRemove(name).?.value;
    self.checkItemUsage(name, item);
}

fn checkIgnore(self: *Self, ignore: *ast.Stmt.Ignore, location: Location) !ControlFlow {
    const info = try self.checkExpr(&ignore.expr, .{});
    if (info.typ.isVoid()) {
        self.failer.fail(location, "redundant ignore", .{});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}

fn checkBreak(self: *Self, location: Location) error{OutOfMemory}!ControlFlow {
    if (self.loops_nested == 0) {
        self.failer.fail(location, "`break` outside of loop", .{});
        return .cont;
    }
    return .brek;
}

fn checkExprStmt(self: *Self, expr: *ast.Expr) !ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try self.checkExpr(expr, .{});
    _ = self.unify(expr.location, .{ .prime = .void }, info.typ);
    return .cont;
}

fn checkWhile(self: *Self, whi: *ast.Stmt.While) !ControlFlow {
    const cf = try self.checkBranch(&whi.branch, true);
    switch (cf) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}

fn checkIf(self: *Self, iff: *ast.Stmt.If) !ControlFlow {
    var res = try self.checkBranch(&iff.branch, false);
    for (iff.else_ifs) |*branch| {
        const cf = try self.checkBranch(branch, false);
        if (@intFromEnum(cf) < @intFromEnum(res)) {
            res = cf;
        }
    }
    const cf = try self.checkBlock(iff.else_branch);
    if (@intFromEnum(cf) < @intFromEnum(res)) {
        res = cf;
    }
    return res;
}

fn checkBranch(self: *Self, branch: *ast.Stmt.Branch, loop: bool) !ControlFlow {
    const info = try self.checkExpr(&branch.condition, .{});
    _ = self.unify(branch.condition.location, .{ .prime = .bool }, info.typ);
    if (loop) {
        return self.checkLoopBlock(branch.body);
    }
    return self.checkBlock(branch.body);
}

fn checkOpAssign(self: *Self, op_assign: *ast.Stmt.OpAssign) !ControlFlow {
    var left = try self.checkExpr(&op_assign.left, .{ .mutable = true });
    if (!left.mutable) {
        self.failer.notMut(op_assign.left.location);
    }
    std.debug.assert(op_assign.kind.getClass() == .arith);
    if (!left.typ.isNumber()) {
        self.failer.wrongTyp(op_assign.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try self.checkExpr(&op_assign.right, .{});
    _ = self.unify(op_assign.right.location, left.typ, right.typ);
    return .cont;
}

fn checkAssign(self: *Self, assign: *ast.Stmt.Assign) !ControlFlow {
    const left = try self.checkExpr(&assign.left, .{ .mutable = true });
    if (!left.mutable) {
        self.failer.notMut(assign.left.location);
    }
    const info = try self.checkExpr(&assign.expr, .{ .typ = left.typ });
    _ = self.unify(assign.expr.location, left.typ, info.typ);
    return .cont;
}

fn checkUnary(self: *Self, unary: *ast.Expr.Unary, location: Location, hint: Typ) !ExprInfo {
    switch (unary.kind) {
        .deref => return self.checkDeref(&unary.expr, location),
        .notb => return self.checkNotb(&unary.expr),
        .ptr => return self.checkPtr(&unary.expr, hint),
        .neg => return self.checkNeg(&unary.expr),
    }
}

fn checkNeg(self: *Self, expr: *ast.Expr) !ExprInfo {
    var info = try self.checkExpr(expr, .{});
    if (!info.typ.isNumber()) {
        self.failer.wrongTyp(expr.location, .int, info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}

fn checkDeref(self: *Self, expr: *ast.Expr, location: Location) !ExprInfo {
    const info = try self.checkExpr(expr, .{});
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
        .prime, .name, .any, .array, .slice, .fun, .int, .loc_name => {
            self.failer.fail(location, "cannot dereference type `{f}`", .{info.typ});
            return err;
        },
        .lazy => unreachable,
    }
}

fn checkElem(self: *Self, elem: *ast.Expr.Elem, location: Location) !ExprInfo {
    const info = try self.checkExpr(&elem.expr, .{});
    const index = try self.checkExpr(&elem.index, .{});
    _ = self.unify(elem.index.location, .{ .prime = .u64 }, index.typ);
    return self.getElemExprInfo(info, location) orelse .{
        .typ = .err,
        .mutable = true,
    };
}

fn getElemExprInfo(self: *Self, info: ExprInfo, location: Location) ?ExprInfo {
    switch (info.typ.normalise()) {
        .array => |array| return .{
            .typ = array.typ.*,
            .mutable = info.mutable,
        },
        .slice => |slice| return .{
            .typ = slice.typ.*,
            .mutable = slice.mutable,
        },
        .err => return null,
        .prime, .name, .loc_name, .ptr, .any, .fun, .int => {
            self.failer.fail(location, "type `{f}` does not support indexing", .{info.typ});
            return null;
        },
        .lazy => unreachable,
    }
}

fn unify(self: *Self, location: Location, a: Typ, b: Typ) Typ {
    if (a.unify(b, true)) |typ| {
        if (Typ.debug_unify) {
            std.debug.print("==> {f}\n", .{typ});
        }
        return typ;
    }
    self.failer.wrongTyp(location, a, b);
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

fn checkDeclare(
    self: *Self,
    name: []const u8,
    declare: *ast.Stmt.Declare,
    location: Location,
) !ControlFlow {
    const typ_decl = if (declare.typ) |typ| typ else .any;
    const info = try self.checkExpr(&declare.expr, .{ .typ = typ_decl });
    const typ = self.unify(declare.expr.location, typ_decl, info.typ);
    try self.declareVar(name, .{
        .typ = typ,
        .mutable = declare.mutable,
        .can_be_mutable = true,
    }, location);
    return .cont;
}

fn declareVar(self: *Self, name: []const u8, vari: Var, location: Location) !void {
    if (self.items.get(name)) |prev| {
        self.failer.alreadyDeclared(location, name, prev.location);
        return;
    }
    try self.vars_stack.append(self.gpa, name);
    try self.items.put(name, .{
        .location = location,
        .kind = .{ .vari = vari },
    });
}

fn checkExpr(self: *Self, expr: *ast.Expr, hint: ExprHint) error{OutOfMemory}!ExprInfo {
    switch (expr.kind) {
        .method => unreachable,
        .subslice => |subslice| return self.checkSubslice(subslice, expr.location),
        .sizeof => |typ| return checkSizeof(typ),
        .array => |*array| return self.checkArray(array, hint.typ, expr.location),
        .unary => |unary| return self.checkUnary(unary, expr.location, hint.typ),
        .struc => |*struc| return self.checkStructExpr(struc, expr.location, hint.typ),
        .int => |*int| return self.checkInt(int, expr.location),
        .str => return self.checkStr(),
        .vari => |*vari| return self.checkVar(vari, expr.location, hint.mutable),
        .char => return .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => return .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |*undef| return checkUndef(undef, hint.typ),
        .call => |call| return self.checkCall(call, hint.typ),
        .binary => |binary| return self.checkBinary(binary),
        .field => |field| return self.checkField(field, expr.location, hint.mutable),
        .named_struc => |*struc| return self.checkNamedStructExpr(struc, expr.location),
        .elem => |elem| return self.checkElem(elem, expr.location),
    }
}

fn checkSubslice(self: *Self, subslice: *ast.Expr.Subslice, location: Location) !ExprInfo {
    const info = try self.checkExpr(&subslice.expr, .{});
    const start = try self.checkExpr(&subslice.start, .{});
    _ = self.unify(subslice.start.location, .{ .prime = .u64 }, start.typ);
    const end = try self.checkExpr(&subslice.end, .{});
    _ = self.unify(subslice.end.location, .{ .prime = .u64 }, end.typ);
    switch (info.typ.normalise()) {
        .array => |array| return .{
            .typ = .{ .slice = .{
                .typ = array.typ,
                .mutable = info.mutable,
            } },
            .mutable = false,
        },
        .slice => return .{
            .typ = info.typ,
            .mutable = info.mutable,
        },
        else => |typ| {
            self.failer.fail(location, "cannot take slice of `{f}`", .{typ});
            return .{
                .typ = .{ .slice = .{
                    .typ = try self.typ_mem.box(.err),
                    .mutable = true,
                } },
                .mutable = false,
            };
        },
    }
}

fn checkSizeof(typ: Typ) !ExprInfo {
    _ = typ;
    return .{
        .typ = .{ .prime = .u64 },
        .mutable = false,
    };
}

fn checkArray(self: *Self, array: *ast.Expr.Array, hint: Typ, location: Location) !ExprInfo {
    var inner_typ: Typ = .any;
    var inner_hint: Typ = .any;
    if (array.mtyp) |typ| {
        inner_typ = typ;
        inner_hint = typ;
    } else if (hint == .array) {
        inner_hint = hint.array.typ.*;
    }
    if (array.exprs.len == 0) {
        const typ = Typ{ .array = .{
            .typ = try self.typ_mem.box(inner_hint),
            .len = 0,
        } };
        return .{
            .typ = typ,
            .mutable = false,
        };
    }
    for (array.exprs) |*expr| {
        const info = try self.checkExpr(expr, .{ .typ = inner_hint });
        inner_typ = self.unify(expr.location, inner_typ, info.typ);
    }
    array.typ = Typ{ .array = .{
        .typ = try self.typ_mem.box(inner_typ),
        .len = array.exprs.len,
    } };
    try self.solve_queue.append(self.gpa, .{
        .typ = &array.typ,
        .location = location,
    });
    return .{
        .typ = array.typ,
        .mutable = false,
    };
}

fn checkStr(self: *Self) !ExprInfo {
    const ptr = try self.typ_mem.box(.{ .prime = .u8 });
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .mutable = false,
        } },
        .mutable = false,
    };
}

fn checkNotb(self: *Self, expr: *ast.Expr) !ExprInfo {
    var info = try self.checkExpr(expr, .{});
    if (!info.typ.isNumber()) {
        self.failer.wrongTyp(expr.location, .int, info.typ);
        info.typ = .err;
    }
    return .{
        .typ = info.typ,
        .mutable = false,
    };
}

fn checkPtr(self: *Self, expr: *ast.Expr, hint: Typ) !ExprInfo {
    const mutable = if (hint == .ptr) hint.ptr.mutable else false;
    const info = try self.checkExpr(expr, .{ .mutable = mutable });
    const ptr = try self.typ_mem.box(info.typ);
    return .{
        .typ = .{ .ptr = .{
            .typ = ptr,
            .mutable = info.mutable,
        } },
        .mutable = false,
    };
}

fn checkStructExpr(
    self: *Self,
    struc: *ast.Expr.Struct,
    location: Location,
    hint: Typ,
) error{OutOfMemory}!ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const name = switch (hint) {
        .loc_name => |located| located.name,
        .name => |name| name,
        .slice => |slice| return self.checkSliceStruc(
            slice,
            struc.fields,
            &struc.typ,
            location,
        ),
        .err => return err,
        .lazy => unreachable,
        .prime, .ptr, .any, .array, .fun, .int => {
            self.failer.cannotInfer(.any, location);
            for (struc.fields) |*field| {
                _ = try self.checkExpr(&field.expr, .{});
            }
            return err;
        },
    };
    return self.checkTypedStruc(name, struc, location);
}

fn checkSliceStruc(
    self: *Self,
    slice: Typ.Slice,
    fields: []ast.Expr.Struct.Field,
    typ_target: *Typ,
    location: Location,
) !ExprInfo {
    var was_ptr: ?*const Typ = null;
    var was_len = false;
    for (fields) |*field| {
        if (std.mem.eql(u8, field.name, "ptr")) {
            if (was_ptr) |_| {
                self.failer.newFieldSecond(field.location, field.name);
            }
            const expected = Typ{ .ptr = .{
                .typ = slice.typ,
                .mutable = slice.mutable,
            } };
            const info = try self.checkExpr(&field.expr, .{ .typ = expected });
            const typ = self.unify(field.expr.location, expected, info.typ);
            was_ptr = if (typ == .ptr) typ.ptr.typ else try self.typ_mem.box(.err);
        } else if (std.mem.eql(u8, field.name, "len")) {
            if (was_len) {
                self.failer.newFieldSecond(field.location, field.name);
            }
            const info = try self.checkExpr(&field.expr, .{ .typ = .{ .prime = .u64 } });
            _ = self.unify(field.expr.location, .{ .prime = .u64 }, info.typ);
            was_len = true;
        }
    }
    if (!was_len) {
        self.failer.notInit(location, "len");
    }
    if (was_ptr == null) {
        self.failer.notInit(location, "ptr");
    }
    typ_target.* = Typ{ .slice = .{
        .typ = was_ptr.?,
        .mutable = slice.mutable,
    } };
    return .{
        .typ = typ_target.*,
        .mutable = false,
    };
}

fn checkTypedStruc(
    self: *Self,
    name: Typ.Name,
    struc: *ast.Expr.Struct,
    location: Location,
) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = false,
    };
    const item = self.items.getPtr(name.name) orelse {
        self.failer.notDeclared(location, name.name);
        return err;
    };
    item.used = true;
    const decl = if (item.kind == .struc) item.kind.struc else {
        self.failer.notStruct(location, .{ .name = name });
        return err;
    };
    var generics = name.generics;
    if (name.generics.len == 0) {
        generics = try self.makeGenerics(decl.generics.len);
    }
    defer if (name.generics.len == 0) {
        defer self.typ_mem.free(generics);
    };
    var resolve_map: std.StringHashMap(Typ) = .init(self.gpa);
    defer resolve_map.deinit();
    for (decl.generics, generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    for (struc.fields) |*field| {
        try self.checkNewField(field, .{ .name = name }, decl.fields, resolve_map);
    }
    self.checkFieldsInitialised(decl.fields, struc.fields, location);
    struc.typ = Typ{ .name = .{
        .generics = try self.typ_mem.save(generics),
        .name = name.name,
    } };
    try self.solve_queue.append(self.gpa, .{
        .typ = &struc.typ,
        .location = location,
    });
    return .{
        .typ = struc.typ,
        .mutable = false,
    };
}

fn makeGenerics(self: *Self, len: usize) ![]const Typ {
    const res = try self.typ_mem.alloc(len);
    for (res) |*target| {
        const lazy = try self.fun_arena.allocator().create(Typ);
        lazy.* = .any;
        target.* = .{ .lazy = lazy };
    }
    return res;
}

fn checkFieldsInitialised(
    self: *Self,
    decl_fields: std.StringHashMap(Field),
    fields: []const ast.Expr.Struct.Field,
    location: Location,
) void {
    var iter = decl_fields.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.defaulted) {
            continue;
        }
        var not_init = true;
        for (fields) |field| {
            if (std.mem.eql(u8, entry.key_ptr.*, field.name)) {
                not_init = false;
                break;
            }
        }
        if (not_init) {
            self.failer.notInit(location, entry.key_ptr.*);
        }
    }
}

fn checkNewField(
    self: *Self,
    field: *ast.Expr.Struct.Field,
    struc_typ: Typ,
    decl_fields: std.StringHashMap(Field),
    resolve_map: std.StringHashMap(Typ),
) !void {
    const f_decl = decl_fields.get(field.name) orelse {
        self.failer.noField(field.location, field.name, struc_typ);
        return;
    };
    const decl_typ = try f_decl.typ.resolve(self.makeResolver(resolve_map));
    const info = try self.checkExpr(&field.expr, .{ .typ = decl_typ });
    _ = self.unify(field.expr.location, decl_typ, info.typ);
}

fn makeResolver(self: Self, map: std.StringHashMap(Typ)) Typ.Resolver {
    return .{ .map = map, .mem = self.typ_mem };
}

fn checkNamedStructExpr(self: *Self, named: *ast.Expr.Struct.Named, location: Location) !ExprInfo {
    return self.checkTypedStruc(.{ .name = named.name }, &named.struc, location);
}

fn checkUndef(undef: *ast.Expr.Undef, typ: Typ) !ExprInfo {
    undef.typ = typ;
    return .{
        .typ = undef.typ,
        .mutable = false,
    };
}

fn checkInt(self: *Self, int: *ast.Expr.Int, location: Location) !ExprInfo {
    const ptr = try self.fun_arena.allocator().create(Typ);
    ptr.* = .int;
    int.typ = .{ .lazy = ptr };
    try self.solve_queue.append(self.gpa, .{
        .location = location,
        .typ = &int.typ,
    });
    return .{
        .typ = int.typ,
        .mutable = false,
    };
}

fn checkField(
    self: *Self,
    field: *ast.Expr.Field,
    location: Location,
    hint_mutable: bool,
) !ExprInfo {
    var info = try self.checkExpr(&field.expr, .{ .mutable = hint_mutable });
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
        return self.checkSliceField(
            norm.slice,
            info.mutable,
            field.name,
            location,
        );
    }
    const name = self.getTypName(norm, field.expr.location) orelse return err;
    const item = self.items.get(name.name) orelse {
        self.failer.notStruct(field.expr.location, norm);
        return err;
    };
    const struc = if (item.kind == .struc) item.kind.struc else {
        self.failer.notStruct(field.expr.location, norm);
        return err;
    };
    const fiel = struc.fields.getPtr(field.name) orelse {
        self.failer.noField(location, field.name, .{ .name = name });
        return err;
    };
    fiel.used = true;
    var resolve_map: std.StringHashMap(Typ) = .init(self.gpa);
    defer resolve_map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    return .{
        .typ = try fiel.typ.resolve(self.makeResolver(resolve_map)),
        .mutable = info.mutable,
    };
}

fn checkSliceField(
    self: *Self,
    slice: Typ.Slice,
    mutable: bool,
    name: []const u8,
    location: Location,
) !ExprInfo {
    if (std.mem.eql(u8, name, "ptr")) {
        return .{
            .typ = .{ .ptr = .{
                .typ = slice.typ,
                .mutable = slice.mutable,
            } },
            .mutable = mutable,
        };
    }
    if (std.mem.eql(u8, name, "len")) {
        return .{
            .typ = .{ .prime = .u64 },
            .mutable = mutable,
        };
    }
    self.failer.noField(location, name, .{ .slice = slice });
    return .{
        .typ = .err,
        .mutable = true,
    };
}

fn getTypName(self: *Self, norm: Typ, location: Location) ?Typ.Name {
    switch (norm) {
        .err => return null,
        .name => |name| return name,
        .loc_name => |located| return located.name,
        .slice, .array, .any, .lazy, .int => {
            std.log.err("getTypName: {f}", .{norm});
            unreachable;
        },
        .fun, .prime, .ptr => {
            self.failer.notStruct(location, norm);
            return null;
        },
    }
}

fn checkBinary(self: *Self, binary: *ast.Expr.Binary) !ExprInfo {
    var left = try self.checkExpr(&binary.left, .{});
    if (!left.typ.isNumber()) {
        self.failer.wrongTyp(binary.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try self.checkExpr(&binary.right, .{});
    const unityp = self.unify(binary.right.location, left.typ, right.typ);
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
    self: *Self,
    vari: *ast.Expr.Var,
    location: Location,
    hint_mutable: bool,
) !ExprInfo {
    const err = ExprInfo{
        .typ = .err,
        .mutable = true,
    };
    const item = self.items.getPtr(vari.name) orelse {
        self.failer.notDeclared(location, vari.name);
        return err;
    };
    switch (item.kind) {
        .fun => |header| {
            item.used = true;
            vari.fun_meta = .{};
            return self.fillFunMetaHeader(&vari.fun_meta.?, header.*, location);
        },
        .struc, .typ => {
            self.failer.fail(location, "it is a type", .{});
            return err;
        },
        .vari => |*vari_decl| {
            item.used = true;
            if (hint_mutable) {
                if (vari_decl.mutable) {
                    vari_decl.mutated = true;
                } else {
                    if (vari_decl.can_be_mutable) {
                        std.log.info("add `mut` before name in {f}", .{item.location});
                    }
                }
            }
            return .{
                .typ = vari_decl.typ,
                .mutable = vari_decl.mutable,
            };
        },
    }
}

fn fillFunMetaHeader(
    self: *Self,
    fun_meta: *ast.Expr.FunMeta,
    header: ast.Item.Fun.Header,
    location: Location,
) !ExprInfo {
    var resolve_map: std.StringHashMap(Typ) = .init(self.gpa);
    defer resolve_map.deinit();
    for (header.generics) |generic| {
        const ptr = try self.fun_arena.allocator().create(Typ);
        ptr.* = .any;
        try resolve_map.put(generic.name, .{ .lazy = ptr });
    }
    fun_meta.generics = try self.typ_mem.arena.allocator().alloc(Typ, header.generics.len);
    const params = try self.typ_mem.alloc(header.params.len);
    defer self.typ_mem.free(params);
    for (header.params, params) |param, *target| {
        target.* = try param.typ.resolve(self.makeResolver(resolve_map));
    }
    for (fun_meta.generics, header.generics) |*target, generic| {
        target.* = resolve_map.get(generic.name).?;
        try self.solve_queue.append(self.gpa, .{
            .typ = target,
            .location = null,
        });
    }
    const ret_typ = try header.ret_typ.resolve(self.makeResolver(resolve_map));
    fun_meta.typ = .{ .fun = .{
        .params = try self.typ_mem.save(params),
        .ret_typ = try self.typ_mem.box(ret_typ),
    } };
    try self.solve_queue.append(self.gpa, .{
        .typ = &fun_meta.typ,
        .location = location,
    });
    return .{
        .typ = fun_meta.typ,
        .mutable = false,
    };
}

fn checkCall(self: *Self, call: *ast.Expr.Call, hint: Typ) !ExprInfo {
    const callee_info = try self.checkExpr(&call.expr, .{});
    const fun = self.getFunTyp(callee_info.typ, call.expr.location) orelse
        return self.checkBadCall(call);
    // to propagate hint to generics
    _ = fun.ret_typ.unify(hint, true);
    for (call.args, fun.params) |*arg, param| {
        const info = try self.checkExpr(arg, .{ .typ = param.normalise() });
        _ = self.unify(arg.location, param, info.typ);
    }
    return .{
        .typ = fun.ret_typ.*,
        .mutable = false,
    };
}

fn getFunTyp(self: *Self, typ: Typ, location: Location) ?Typ.Fun {
    switch (typ.normalise()) {
        .fun => |fun| return fun,
        .err => return null,
        else => {
            self.failer.fail(location, "value of type `{f}` is not a function", .{typ});
            return null;
        },
    }
}

fn checkBadCall(self: *Self, call: *ast.Expr.Call) !ExprInfo {
    for (call.args) |*arg| {
        _ = try self.checkExpr(arg, .{});
    }
    return .{
        .typ = .err,
        .mutable = false,
    };
}

fn checkRet(self: *Self, ret: *ast.Stmt.Return, location: Location) !ControlFlow {
    if (ret.expr) |*expr| {
        const info = try self.checkExpr(expr, .{ .typ = self.ret_typ });
        _ = self.unify(expr.location, self.ret_typ, info.typ);
    } else if (self.ret_typ != .prime or self.ret_typ.prime != .void) {
        self.failer.fail(location, "should return a value", .{});
    }
    return .ret;
}

fn deinit(self: *Self) void {
    self.deinitItems();
    self.solve_queue.deinit(self.gpa);
    self.fun_arena.deinit();
    self.vars_stack.deinit(self.gpa);
    self.generics_usage.deinit(self.gpa);
    self.* = undefined;
}

fn deinitItems(self: *Self) void {
    var items = self.items.valueIterator();
    while (items.next()) |item| {
        item.deinit();
    }
    self.items.deinit();
}

fn checkTypDecl(self: *Self, located: Typ.Name.Located) error{BadType}!?Typ {
    if (debug_check_typ) {
        std.debug.print("checkTypDecl {f}\n", .{located.name});
    }
    const item = self.items.getPtr(located.name.name) orelse {
        self.failer.fail(located.location, "item `{s}` is not declared", .{located.name.name});
        return error.BadType;
    };
    switch (item.kind) {
        .fun, .vari => {
            self.failer.fail(located.location, "item `{s}` is not a type", .{located.name.name});
            return error.BadType;
        },
        .typ => |typ| {
            item.used = true;
            return typ;
        },
        .struc => |struc| {
            item.used = true;
            if (debug_check_typ) {
                std.debug.print("item {s} used\n", .{located.name.name});
            }
            if (struc.generics.len != located.name.generics.len) {
                self.failer.fail(
                    located.location,
                    "expected {} generics\n        found {}",
                    .{ struc.generics.len, located.name.generics.len },
                );
            }
            return null;
        },
    }
}

const debug_check_typ = false;

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
    generics: []const ast.Item.Generic,
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

const Item = struct {
    const Kind = union(enum) {
        fun: *ast.Item.Fun.Header,
        vari: Var,
        struc: Struct,
        typ: Typ,
    };
    kind: Kind,
    location: Location,
    used: bool = false,

    fn deinit(item: *Item) void {
        switch (item.kind) {
            .struc => |*struc| struc.deinit(),
            .fun, .vari, .typ => {},
        }
    }
};

const SolveRequest = struct {
    location: ?Location,
    typ: *Typ,
};
