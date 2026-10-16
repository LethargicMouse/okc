const std = @import("std");

const Expr = @import("Expr/Expr.zig");
const fail = @import("fail.zig");
const Location = @import("Location.zig");
const Module = @import("Module.zig");
const Stmt = @import("Stmt.zig");
const Typ = @import("typ/typ.zig").Typ;
const Item = @import("Item.zig");

gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
vars_stack: std.ArrayList([]const u8) = .empty,
module: Module.Info,
ret_typ: Typ = .any,
loops_nested: u16 = 0,

pub fn init(
    gpa: std.mem.Allocator,
) error{OutOfMemory}!@This() {
    return .{
        .gpa = gpa,
        .arena = .init(gpa),
        .module = .init(gpa),
    };
}

pub fn run(self: *@This(), module: Module) error{ OutOfMemory, Handled }!void {
    defer self.deinit();
    try self.checkModule(module);
    try fail.ensureNoErrors();
    return;
}

fn checkModule(self: *@This(), module: Module) !void {
    for (module.items) |*item| {
        try self.regItem(item);
    }
    for (module.items) |item| {
        try self.checkItem(item, .{
            .gpa = self.gpa,
            .items = &self.module.items,
            .vars_stack = &self.vars_stack,
        });
    }
    self.checkMain(module.location);
    self.checkItemsUsage();
}

fn checkItemsUsage(self: *@This()) void {
    var iter = self.module.items.iterator();
    while (iter.next()) |entry| {
        checkItemUsage(entry.key_ptr.*, entry.value_ptr.*);
    }
}

fn checkItemUsage(name: []const u8, info: Item.Info) void {
    if (info.used) {
        switch (info.kind) {
            .fun, .typ => {},
            .vari => |vari| checkVarUsage(vari, info.location),
            .struc => |struc| checkStructUsage(struc),
        }
    } else {
        fail.unused(info.location, name);
    }
}

fn checkStructUsage(struc: Item.Struct.Info) void {
    var iter = struc.fields.iterator();
    while (iter.next()) |entry| {
        if (!entry.value_ptr.used) {
            fail.unused(entry.value_ptr.location, entry.key_ptr.*);
        }
    }
}

fn regItem(self: *@This(), item: *Item) !void {
    const kind: Item.Info.Kind = switch (item.kind) {
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
    if (self.module.items.get(item.name)) |prev| {
        fail.alreadyDeclared(item.location, item.name, prev.location);
        return;
    }
    try self.module.items.put(item.name, .{
        .location = item.location,
        .kind = kind,
    });
}

fn regConst(self: *@This(), declare: *Item.Declare) !Item.Info.Kind {
    const hint_typ = if (declare.typ) |typ| typ else .any;
    const typ = try self.checkConstExpr(&declare.expr, .{ .typ = hint_typ }, .{
        .gpa = self.gpa,
        .items = self.module.items,
    });
    if (declare.typ) |typ_decl| {
        _ = typ_decl.unify(typ, declare.expr.location);
    }
    return .{ .vari = .{
        .mutable = false,
        .typ = typ,
        .can_be_mutable = true,
    } };
}

fn checkConstExpr(self: *@This(), expr: *Expr, hint: Expr.Hint, ctx: Expr.Check) !Typ {
    const info = try expr.check(hint, ctx);
    self.checkExprComptime(expr.*);
    return info.typ;
}

fn checkExprComptime(self: *@This(), expr: Expr) void {
    switch (expr.kind) {
        .str, .bool, .char, .int, .sizeof, .vari, .undef => {},
        .call, .method => fail.fail(expr.location, "cannot evaluate at compile time", .{}),
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

fn checkElemComptime(self: *@This(), elem: Expr.Elem) void {
    self.checkExprComptime(elem.expr);
    self.checkExprComptime(elem.index);
}

fn checkBinaryComptime(self: *@This(), binary: Expr.Binary) void {
    self.checkExprComptime(binary.left);
    self.checkExprComptime(binary.right);
}

fn checkSubsliceComptime(self: *@This(), subslice: Expr.Subslice) void {
    self.checkExprComptime(subslice.expr);
    self.checkExprComptime(subslice.start);
    self.checkExprComptime(subslice.end);
}

fn checkStructExprComptime(self: *@This(), struc: Expr.Struct) void {
    for (struc.fields) |field| {
        self.checkExprComptime(field.expr);
    }
}

fn checkArrayComptime(self: *@This(), array: Expr.Array) void {
    for (array.exprs) |elem| {
        self.checkExprComptime(elem);
    }
}

fn checkItem(self: *@This(), item: Item, ctx: Stmt.Check) error{OutOfMemory}!void {
    switch (item.kind) {
        .typ_alias, .constant, .struc, .ext_fun => {},
        .fun => |fun| try self.checkFun(fun, item.location, ctx),
        .use => unreachable,
    }
}

fn checkHeader(self: *@This(), header: *Item.Fun.Header) !void {
    var generics_checker: Item.Generic.Checker = try .init(self.gpa, header.generics);
    defer generics_checker.deinit(self.gpa);
    const typ_check = Typ.Check{
        .generics_checker = &generics_checker,
        .items = self.module.items,
    };
    for (header.params) |*param| {
        param.typ = try param.typ.check(typ_check);
    }
    header.ret_typ = try header.ret_typ.check(typ_check);
    generics_checker.checkUsage();
}

fn checkVarUsage(vari: Item.Declare.Info, location: Location) void {
    if (vari.mutable and !vari.mutated) {
        fail.fail(location, "variable is never mutated", .{});
        std.log.info("remove `mut` before name\n", .{});
    }
}

fn checkMain(self: *@This(), location: Location) void {
    const item = self.module.items.getPtr("main") orelse {
        fail.fail(location, "`main` function not found", .{});
        return;
    };
    if (item.kind != .fun) {
        fail.fail(item.location, "item `main` is not a function", .{});
    }
    item.used = true;
}

fn regStruct(self: *@This(), struc: Item.Struct) !Item.Info.Kind {
    try self.checkGenericsRedeclare(struc.generics);
    var res = Item.Struct.Info{
        .generics = struc.generics,
        .fields = .init(self.gpa),
    };
    for (struc.fields) |*field| {
        var defaulted = false;
        if (field.default) |*expr| {
            const expr_typ = try self.checkConstExpr(expr, .{ .typ = field.typ }, .{
                .gpa = self.gpa,
                .items = self.module.items,
            });
            _ = field.typ.unify(expr_typ, expr.location);
            defaulted = true;
        }
        if (res.fields.get(field.name)) |prev| {
            fail.alreadyDeclared(field.location, field.name, prev.location);
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

fn checkGenericsRedeclare(self: *@This(), generics: []const Item.Generic) !void {
    var map = std.StringHashMap(Location).init(self.gpa);
    defer map.deinit();
    for (generics) |generic| {
        if (self.module.items.get(generic.name)) |prev| {
            fail.alreadyDeclared(generic.location, generic.name, prev.location);
        }
        const entry = try map.getOrPut(generic.name);
        if (entry.found_existing) {
            fail.alreadyDeclared(generic.location, generic.name, entry.value_ptr.*);
        } else {
            entry.value_ptr.* = generic.location;
        }
    }
}

fn checkFun(self: *@This(), fun: Item.Fun, location: Location, ctx: Stmt.Check) !void {
    self.ret_typ = fun.header.ret_typ;
    const rbp = self.vars_stack.items.len;
    for (fun.header.params) |param| {
        const vari: Item.Declare.Info = .{
            .typ = param.typ,
            .mutable = false,
            .can_be_mutable = false,
        };
        try vari.declare(param.name, param.location, ctx);
    }
    const control_flow = try self.checkBlock(fun.body, ctx);
    if (control_flow != .ret and !fun.header.ret_typ.isVoid()) {
        fail.fail(location, "function may not return", .{});
    }
    self.freeVars(rbp);
}

fn checkLoopBlock(self: *@This(), block: []Stmt, ctx: Stmt.Check) !Stmt.ControlFlow {
    self.loops_nested += 1;
    const res = try self.checkBlock(block, ctx);
    self.loops_nested -= 1;
    switch (res) {
        .ret => return .ret,
        .brek, .cont => return .cont,
    }
}

fn checkBlock(self: *@This(), block: []Stmt, ctx: Stmt.Check) !Stmt.ControlFlow {
    var res = Stmt.ControlFlow.cont;
    const rbp = self.vars_stack.items.len;
    for (block, 0..) |*stmt, i| {
        const control_flow = try self.checkStmt(stmt, ctx);
        if (control_flow != .cont) {
            if (res == .cont) {
                res = control_flow;
            }
            if (i + 1 != block.len) {
                fail.fail(block[i + 1].location, "Stmt is unreachable", .{});
            }
        }
    }
    self.freeVars(rbp);
    return res;
}

fn freeVars(self: *@This(), rbp: usize) void {
    for (self.vars_stack.items[rbp..]) |name| {
        self.freeVar(name);
    }
    self.vars_stack.shrinkRetainingCapacity(rbp);
}

fn checkStmt(self: *@This(), stmt: *Stmt, ctx: Stmt.Check) error{OutOfMemory}!Stmt.ControlFlow {
    switch (stmt.kind) {
        .for_range => |*forr| return self.checkForRange(forr, ctx),
        .forr => |*forr| return self.checkFor(forr, ctx),
        .unre => return .ret,
        .brek => return self.checkBreak(stmt.location),
        .ret => |*ret| return ret.check(stmt.location, self.ret_typ, ctx.exprCheck()),
        .expr => |*expr| return checkExprStmt(expr, ctx.exprCheck()),
        .declare => |*named| return named.check(stmt.location, ctx),
        .op_assign => |*op_assign| return checkOpAssign(op_assign, ctx.exprCheck()),
        .assign => |*assign| return checkAssign(assign, ctx.exprCheck()),
        .iff => |*iff| return self.checkIf(iff, ctx),
        .whi => |*whi| return self.checkWhile(whi, ctx),
        .ignore => |*ignore| return checkIgnore(ignore, stmt.location, ctx.exprCheck()),
    }
}

fn checkForRange(self: *@This(), forr: *Stmt.ForRange, ctx: Stmt.Check) !Stmt.ControlFlow {
    var start = try forr.start.check(.{}, ctx.exprCheck());
    if (!start.typ.isNumber()) {
        fail.wrongTyp(forr.start.location, .int, start.typ);
        start.typ = .err;
    }
    const end = try forr.end.check(.{}, ctx.exprCheck());
    const typ = start.typ.unify(end.typ, forr.end.location);
    const vari: Item.Declare.Info = .{
        .typ = typ,
        .mutable = false,
        .can_be_mutable = false,
    };
    try vari.declare(forr.vari, forr.vari_location, ctx);
    defer {
        _ = self.vars_stack.pop();
        self.freeVar(forr.vari);
    }
    return self.checkLoopBlock(forr.body, ctx);
}

fn checkFor(self: *@This(), forr: *Stmt.For, ctx: Stmt.Check) !Stmt.ControlFlow {
    const info = try forr.expr.check(.{}, ctx.exprCheck());
    const elem_info = info.getElem(forr.expr.location) orelse Expr.Info{
        .typ = .err,
        .mutable = true,
    };
    const vari: Item.Declare.Info = .{
        .typ = elem_info.typ,
        .mutable = false,
        .can_be_mutable = false,
    };
    try vari.declare(forr.vari, forr.vari_location, ctx);
    defer {
        _ = self.vars_stack.pop();
        self.freeVar(forr.vari);
    }
    return self.checkLoopBlock(forr.body, ctx);
}

fn freeVar(self: *@This(), name: []const u8) void {
    const item = self.module.items.fetchRemove(name).?.value;
    checkItemUsage(name, item);
}

fn checkIgnore(ignore: *Stmt.Ignore, location: Location, ctx: Expr.Check) !Stmt.ControlFlow {
    const info = try ignore.expr.check(.{}, ctx);
    if (info.typ.isVoid()) {
        fail.fail(location, "redundant ignore", .{});
        std.log.info("remove `_ =` before expr\n", .{});
    }
    return .cont;
}

fn checkBreak(self: *@This(), location: Location) error{OutOfMemory}!Stmt.ControlFlow {
    if (self.loops_nested == 0) {
        fail.fail(location, "`break` outside of loop", .{});
        return .cont;
    }
    return .brek;
}

fn checkExprStmt(expr: *Expr, ctx: Expr.Check) !Stmt.ControlFlow {
    // no type hints to disallow `undefined;`
    const info = try expr.check(.{}, ctx);
    const expected: Typ = .{ .prime = .void };
    _ = expected.unify(info.typ, expr.location);
    return .cont;
}

fn checkWhile(self: *@This(), whi: *Stmt.While, ctx: Stmt.Check) !Stmt.ControlFlow {
    const control_flow = try self.checkBranch(&whi.branch, .loop, ctx);
    switch (control_flow) {
        .cont, .brek => return .cont,
        .ret => return .ret,
    }
}

fn checkIf(self: *@This(), iff: *Stmt.IfStmt, ctx: Stmt.Check) !Stmt.ControlFlow {
    var res = try self.checkBranch(&iff.branch, .simple, ctx);
    for (iff.else_ifs) |*branch| {
        const control_flow = try self.checkBranch(branch, .simple, ctx);
        if (@backingInt(control_flow) < @backingInt(res)) {
            res = control_flow;
        }
    }
    const control_flow = try self.checkBlock(iff.else_branch, ctx);
    if (@backingInt(control_flow) < @backingInt(res)) {
        res = control_flow;
    }
    return res;
}

fn checkBranch(
    self: *@This(),
    branch: *Stmt.Branch,
    kind: Stmt.Branch.Kind,
    ctx: Stmt.Check,
) !Stmt.ControlFlow {
    const info = try branch.condition.check(.{}, ctx.exprCheck());
    const expected: Typ = .{ .prime = .bool };
    _ = expected.unify(info.typ, branch.condition.location);
    if (kind == .loop) {
        return self.checkLoopBlock(branch.body, ctx);
    }
    return self.checkBlock(branch.body, ctx);
}

fn checkOpAssign(op_assign: *Stmt.OpAssign, ctx: Expr.Check) !Stmt.ControlFlow {
    var left = try op_assign.left.check(.{ .mutable = true }, ctx);
    if (!left.mutable) {
        fail.notMut(op_assign.left.location);
    }
    std.debug.assert(op_assign.kind.getClass() == .arith);
    if (!left.typ.isNumber()) {
        fail.wrongTyp(op_assign.left.location, .int, left.typ);
        left.typ = .err;
    }
    const right = try op_assign.right.check(.{}, ctx);
    _ = left.typ.unify(right.typ, op_assign.right.location);
    return .cont;
}

fn checkAssign(assign: *Stmt.Assign, ctx: Expr.Check) !Stmt.ControlFlow {
    const left = try assign.left.check(.{ .mutable = true }, ctx);
    if (!left.mutable) {
        fail.notMut(assign.left.location);
    }
    const info = try assign.expr.check(.{ .typ = left.typ }, ctx);
    _ = left.typ.unify(info.typ, assign.expr.location);
    return .cont;
}

fn deinit(self: *@This()) void {
    self.module.deinit();
    self.vars_stack.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}
