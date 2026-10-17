const std = @import("std");

const okc = @import("okc");

io: std.Io, // expr
gpa: std.mem.Allocator, // expr
arena: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
buffer: ?std.ArrayList(u8) = null,
extra_buffer: std.ArrayList(u8) = .empty,
items: std.StringHashMap(okc.Item),
structs: okc.HashMap(okc.Typ.Name, okc.Item.Struct.GenInfo),
consts: std.StringHashMap(okc.Typ),
vars: std.StringHashMap(okc.Val.Ref),
loop_ends: std.ArrayList(u32) = .empty,
fun_queue: std.ArrayList(FunReq) = .empty,
generated: okc.HashMap(okc.Typ.Name, void),
resolve_map: std.StringHashMap(okc.Typ),
next_tmp: u32 = 0,

const FunReq = struct {
    name: okc.Typ.Name,
    fun: okc.Typ.Fun,
};

pub fn init(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    write_buf: []u8,
    path: []const u8,
) error{ OutOfMemory, Handled }!@This() {
    const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch {
        std.log.err("failed to create `{s}`", .{path});
        return error.Handled;
    };
    return .{
        .io = io,
        .gpa = gpa,
        .arena = arena,
        .file = file,
        .items = .init(gpa),
        .resolve_map = .init(gpa),
        .writer = file.writer(io, write_buf),
        .vars = .init(gpa),
        .structs = .init(gpa),
        .consts = .init(gpa),
        .generated = .init(gpa),
    };
}

pub fn run(self: *@This(), module: okc.Module) error{ WriteFailed, OutOfMemory }!void {
    defer self.deinit();
    for (module.items) |item| {
        try self.items.put(item.name, item);
    }
    try self.genAll();
    try self.writer.interface.flush();
}

fn genAll(self: *@This()) !void {
    try self.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    try self.genSliceDecl();
    try self.genFunNamed(.{
        .name = .{ .name = "main" },
        .fun = .{
            .params = &.{},
            .ret_typ = try okc.Typ.memo.box(.{ .prime = .i32 }, self.arena),
        },
    });
    while (self.fun_queue.items.len != 0) {
        const req = self.fun_queue.pop().?;
        try self.genFunNamed(req);
    }
    try self.print("\n", .{});
}

fn genFunNamed(self: *@This(), req: FunReq) !void {
    const item = self.items.get(req.name.name).?;
    const fun = switch (item.kind) {
        .typ_alias, .use => unreachable,
        .ext_fun => |ext_fun| {
            const was = try self.generated.getOrPut(req.name);
            if (was.found_existing) {
                return;
            }
            try self.genExtFun(req.name.name, ext_fun);
            return;
        },
        .fun => |fun| fun,
        .constant, .struc => unreachable,
    };
    const was = try self.generated.getOrPut(req.name);
    if (was.found_existing) {
        return;
    }
    for (fun.header.generics, req.name.generics) |generic, typ| {
        try self.resolve_map.put(generic.name, typ);
    }
    try self.genFun(req.name, fun, req.fun);
}

fn genSliceDecl(self: *@This()) !void {
    try self.print("\n%\"[]\" = type {{ ptr, i64 }}", .{});
}

fn genExtFun(self: *@This(), name: []const u8, ext_fun: okc.Item.Fun.Extern) !void {
    try self.print("\ndeclare {f} @{s}(", .{
        okc.Typ.LLPrinter{ .typ = ext_fun.header.ret_typ },
        name,
    });
    if (ext_fun.header.params.len != 0) {
        try self.print("{f}", .{okc.Typ.LLPrinter{ .typ = ext_fun.header.params[0].typ }});
        for (ext_fun.header.params[1..]) |param| {
            try self.print(", {f}", .{okc.Typ.LLPrinter{ .typ = param.typ }});
        }
    }
    try self.print(")", .{});
}

fn genStrDecl(self: *@This(), str: []const u8) !okc.Expr.Str.GenInfo {
    const buffer = self.buffer.?;
    self.buffer = null;
    defer self.buffer = buffer;
    const unescaped = try unescape(self.gpa, str);
    defer self.gpa.free(unescaped.repr);
    const tmp = self.newTmp();
    try self.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
        tmp,
        unescaped.len + 1,
        unescaped.repr,
    });
    return .{
        .len = unescaped.len,
        .tmp = tmp,
    };
}

fn unescape(gpa: std.mem.Allocator, str: []const u8) !okc.Expr.Str.Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, str.len);
    var i: usize = 0;
    var len = str.len;
    while (i < str.len) : (i += 1) {
        if (str[i] == '\\') {
            i += 1;
            len -= 1;
            switch (str[i]) {
                'n' => try vec.appendSlice(gpa, "\\0A"),
                'x' => {
                    try vec.append(gpa, '\\');
                    try vec.appendSlice(gpa, str[i + 1 .. i + 3]);
                    i += 2;
                    len -= 2;
                },
                else => {
                    std.log.err("bad escape symbol: `\\{c}`", .{str[i]});
                    // supposed to be checked by `Checker`
                    unreachable;
                },
            }
        } else {
            try vec.append(gpa, str[i]);
        }
    }
    const repr = try vec.toOwnedSlice(gpa);
    return .{
        .len = len,
        .repr = repr,
    };
}

fn genFun(
    self: *@This(),
    name: okc.Typ.Name,
    fun: okc.Item.Fun,
    fun_typ: okc.Typ.Fun,
) !void {
    self.buffer = self.extra_buffer;
    try self.print(
        "\ndefine {f} @\"{f}\"(",
        .{ okc.Typ.LLPrinter{ .typ = fun_typ.ret_typ.* }, name },
    );
    var param_typ_vals = try self.gpa.alloc(okc.Val.Typed, fun.header.params.len);
    defer self.gpa.free(param_typ_vals);
    if (fun.header.params.len != 0) {
        param_typ_vals[0] = try self.genParam(fun_typ.params[0]);
        for (param_typ_vals[1..], fun_typ.params[1..]) |*target, param_typ| {
            try self.print(", ", .{});
            target.* = try self.genParam(param_typ);
        }
    }
    try self.print(
        \\) {{
        \\entry:
    , .{});
    self.extra_buffer = self.buffer.?;
    self.buffer = .empty;
    for (
        param_typ_vals[0..fun.header.params.len],
        fun.header.params,
    ) |typ_val, param| {
        const vari = try self.toStack(typ_val);
        try self.vars.put(param.name, vari);
    }
    for (fun.body.stmts) |stmt| {
        try self.genStmt(stmt);
    }
    if (fun.header.ret_typ.isVoid()) {
        try self.genRet(.{ .expr = null });
    } else {
        try self.genUnreachable();
    }
    try self.print("\n}}", .{});
    var buffer = self.buffer.?;
    defer buffer.deinit(self.gpa);
    self.buffer = null;
    try self.print("{s}{s}", .{ self.extra_buffer.items, buffer.items });
    self.extra_buffer.clearRetainingCapacity();
    self.vars.clearRetainingCapacity();
    self.resolve_map.clearRetainingCapacity();
}

fn genStruct(self: *@This(), name: okc.Typ.Name) Error!void {
    const was = try self.generated.getOrPut(name);
    if (was.found_existing) {
        return;
    }
    const buffer = self.buffer.?;
    self.buffer = .empty;
    defer {
        if (self.buffer) |*buf| {
            buf.deinit(self.gpa);
        }
        self.buffer = buffer;
    }
    var fields: std.StringHashMap(okc.Item.Struct.Field.GenInfo) = .init(self.gpa);
    errdefer fields.deinit();
    var default_fields_vec: std.ArrayList(okc.Item.Struct.Field.DefaultedGenInfo) = .empty;
    errdefer default_fields_vec.deinit(self.gpa);
    try self.print("\n%\"{f}\" = type {{", .{name});
    const struc = self.items.get(name.name).?.kind.struc;
    var resolve_map: std.StringHashMap(okc.Typ) = .init(self.gpa);
    defer resolve_map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    var struct_layout = okc.Layout{ .size = 0, .alig = 1 };
    const field_typs = try self.gpa.alloc(okc.Typ, struc.fields.len);
    defer self.gpa.free(field_typs);
    for (field_typs, struc.fields, 0..) |*typ, field, i| {
        typ.* = try field.typ.resolve(resolve_map, self.arena);
        const layout = try self.getLayout(typ.*);
        struct_layout.add(layout);
        try fields.put(field.name, .{
            .typ = typ.*,
            .index = i,
        });
        if (field.default) |expr| {
            try default_fields_vec.append(self.gpa, .{
                .expr = expr,
                .index = i,
            });
        }
    }
    if (field_typs.len != 0) {
        try self.print("\n  {f}", .{okc.Typ.LLPrinter{ .typ = field_typs[0] }});
        for (field_typs[1..]) |typ| {
            try self.print(",\n  {f}", .{okc.Typ.LLPrinter{ .typ = typ }});
        }
    }
    try self.print("\n}}", .{});
    var written = self.buffer.?;
    self.buffer = null;
    defer written.deinit(self.gpa);
    try self.print("{s}", .{written.items});
    try self.structs.put(name, .{
        .fields = fields,
        .default_fields = try default_fields_vec.toOwnedSlice(self.gpa),
        .layout = struct_layout,
    });
}

fn genParam(self: *@This(), typ: okc.Typ) !okc.Val.Typed {
    const tmp = self.newTmp();
    try self.print("{f} %t{}", .{ okc.Typ.LLPrinter{ .typ = typ }, tmp });
    return .{ .typ = typ, .bare = .{ .tmp = tmp } };
}

fn genStmt(self: *@This(), stmt: okc.Stmt) Error!void {
    switch (stmt.kind) {
        .for_range => |forr| try self.genForRange(forr),
        .forr => |forr| try self.genFor(forr),
        .op_assign => |op_assign| try self.genOpAssign(op_assign),
        .unre => try self.genUnreachable(),
        .ret => |ret| try self.genRet(ret),
        .expr => |expr| _ = try self.genExpr(expr.expr),
        .declare => |named| try self.genDeclare(named.name, named.bare),
        .assign => |assign| try self.genAssign(assign),
        .iff => |iff| try self.genIf(iff),
        .whi => |whi| try self.genWhile(whi),
        .ignore => |ignore| try self.genIgnore(ignore),
        .brek => try self.genBreak(),
    }
}

fn genUnreachable(self: *@This()) !void {
    try self.print("\n  unreachable", .{});
}

fn genIgnore(self: *@This(), ignore: okc.Stmt.Ignore) !void {
    _ = try self.genExpr(ignore.expr);
}

fn genBreak(self: *@This()) !void {
    const label = self.newTmp();
    try self.uncond(self.loop_ends.getLast(), label);
}

fn genWhile(self: *@This(), whi: okc.Stmt.While) !void {
    const condition_label = self.newTmp();
    try self.uncond(condition_label, condition_label);
    try self.genBranch(whi.branch, condition_label, .loop);
}

fn genForRange(self: *@This(), forr: okc.Stmt.ForRange) !void {
    // int i = start
    try self.genDeclare(forr.vari, .{
        .expr = forr.start,
        .typ = null,
        .mutable = false,
    });
    const end = try self.genExpr(forr.end);
    // goto cond
    // start:
    const start_label = self.newTmp();
    const cond_label = self.newTmp();
    try self.uncond(cond_label, start_label);
    // i++
    const ival = try self.genVar(.{ .name = forr.vari });
    const inew = try self.genBinary(.add, ival.typ, ival.bare, .{ .int = 1 });
    try self.storeInto(
        self.vars.get(forr.vari).?.val,
        .{ .typ = ival.typ, .bare = .{ .tmp = inew } },
    );
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i != end
    const ival_ = try self.loadTypVal(self.vars.get(forr.vari).?);
    const at_end = try self.genBinary(.neq, ival.typ, ival_.bare, end.bare);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = at_end }, body_label, end_label);
    // <body>
    for (forr.body.stmts) |stmt| {
        try self.genStmt(stmt);
    }
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

fn genFor(self: *@This(), forr: okc.Stmt.For) !void {
    const slice = try self.genExprRef(forr.expr);
    // int i = 0
    const iref = try self.toStack(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = 0 },
    });
    // goto cond
    // start:
    const start_label = self.newTmp();
    const cond_label = self.newTmp();
    try self.uncond(cond_label, start_label);
    // i++
    const ival = try self.loadTypVal(iref);
    const inew = try self.genBinary(.add, ival.typ, ival.bare, .{ .int = 1 });
    try self.storeInto(iref.val, .{ .typ = ival.typ, .bare = .{ .tmp = inew } });
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i < .len
    const ival_ = try self.loadTypVal(iref);
    const len = try self.genField(.{
        .expr = forr.expr,
        .name = "len",
    });
    const less = try self.genBinary(.les, ival.typ, ival_.bare, len.bare);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = less }, body_label, end_label);
    // var = slice[i]
    const elem = try self.genElemRef(slice, ival_);
    try self.vars.put(forr.vari, elem);
    // <body>
    for (forr.body.stmts) |stmt| {
        try self.genStmt(stmt);
    }
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

fn cond(
    self: *@This(),
    condition: okc.Val,
    then_label: u32,
    else_label: u32,
) !void {
    try self.print(
        \\
        \\  br i1 {f}, label %l{}, label %l{}
        \\l{}:
    , .{
        condition,
        then_label,
        else_label,
        then_label,
    });
}

fn uncond(self: *@This(), to: u32, next: u32) !void {
    try self.print(
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
}

fn genIf(self: *@This(), iff: okc.Stmt.IfStmt) !void {
    const end_label = self.newTmp();
    try self.genBranch(iff.branch, end_label, .simple);
    for (iff.else_ifs) |branch| {
        try self.genBranch(branch, end_label, .simple);
    }
    for (iff.else_block.stmts) |stmt| {
        try self.genStmt(stmt);
    }
    try self.uncond(end_label, end_label);
}

fn genBranch(self: *@This(), branch: okc.Stmt.Branch, end_label: u32, kind: okc.Stmt.Branch.Kind) !void {
    const condition = try self.genExpr(branch.condition);
    const then_label = self.newTmp();
    const else_label = self.newTmp();
    if (kind == .loop) {
        try self.loop_ends.append(self.gpa, else_label);
    }
    try self.cond(condition.bare, then_label, else_label);
    for (branch.body.stmts) |stmt| {
        try self.genStmt(stmt);
    }
    try self.uncond(end_label, else_label);
    if (kind == .loop) {
        _ = self.loop_ends.pop();
    }
}

fn genOpAssign(self: *@This(), op_assign: okc.Stmt.OpAssign) !void {
    const vari = try self.genExprRef(op_assign.left);
    const typ_val = try self.genBinaryExpr(.{
        .left = op_assign.left,
        .kind = op_assign.kind,
        .right = op_assign.right,
    });
    try self.storeInto(vari.val, typ_val);
}

fn genAssign(self: *@This(), assign: okc.Stmt.Assign) !void {
    const vari = try self.genExprRef(assign.left);
    const typ_val = try self.genExpr(assign.expr);
    try self.storeInto(vari.val, typ_val);
}

fn genDeclare(self: *@This(), name: []const u8, declare: okc.Stmt.Declare) !void {
    const typ_val = try self.genExpr(declare.expr);
    const vari = try self.toStack(typ_val);
    try self.vars.put(name, vari);
}

fn toStack(self: *@This(), typ_val: okc.Val.Typed) !okc.Val.Ref {
    if (typ_val.typ.getName()) |typ_name| {
        try self.genStruct(typ_name);
    }
    const tmp = self.newTmp();
    try self.genAlloca(tmp, typ_val.typ);
    try self.storeInto(.{ .tmp = tmp }, typ_val);
    return .{
        .val = .{ .tmp = tmp },
        .inner_typ = typ_val.typ,
    };
}

fn genAlloca(self: *@This(), tmp: u32, typ: okc.Typ) !void {
    const buffer = self.buffer;
    // so that all allocs are in entry block
    self.buffer = self.extra_buffer;
    defer {
        self.extra_buffer = self.buffer.?;
        self.buffer = buffer;
    }
    try self.print("\n  %t{} = alloca {f}", .{ tmp, okc.Typ.LLPrinter{ .typ = typ } });
}

fn storeInto(self: *@This(), val: okc.Val, typ_val: okc.Val.Typed) !void {
    try self.print("\n  store {f}, ptr {f}", .{ typ_val, val });
}

fn genCall(self: *@This(), call: okc.Expr.Call) !okc.Val.Typed {
    const callee = try self.genExpr(call.expr);
    var arg_typ_vals = try self.gpa.alloc(okc.Val.Typed, call.args.len);
    defer self.gpa.free(arg_typ_vals);
    for (arg_typ_vals, call.args, callee.typ.fun.params) |*target, arg, param| {
        target.* = try self.genExpr(arg);
        if (param == .slice and target.typ == .ptr) {
            target.* = try self.genArrayToSlice(target.typ.ptr.typ.array, target.bare);
        }
    }
    const ret_tmp = self.newTmp();
    if (callee.typ.fun.ret_typ.* != .prime or callee.typ.fun.ret_typ.prime != .void) {
        try self.print("\n  %t{} = ", .{ret_tmp});
    } else {
        try self.print("\n  ", .{});
    }
    try self.print("call {f} {f} (", .{
        okc.Typ.LLPrinter{ .typ = callee.typ.fun.ret_typ.* },
        callee.bare,
    });
    if (call.args.len != 0) {
        try self.print("{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try self.print(", {f}", .{val});
        }
    }
    try self.print(")", .{});
    return .{
        .typ = callee.typ.fun.ret_typ.*,
        .bare = .{ .tmp = ret_tmp },
    };
}

fn genArrayToSlice(self: *@This(), array: okc.Typ.Array, val: okc.Val) !okc.Val.Typed {
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .bare = .undef,
    };
    try self.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .bare = val,
    }, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = array.len },
    }, 1);
    return res;
}

fn newTmp(self: *@This()) u32 {
    self.next_tmp += 1;
    return self.next_tmp - 1;
}

fn genRet(self: *@This(), ret: okc.Stmt.Return) !void {
    if (ret.expr) |expr| {
        const val = try self.genExpr(expr);
        try self.print("\n  ret {f}", .{val});
    } else {
        try self.print("\n  ret void", .{});
    }
}

fn genExpr(self: *@This(), expr: okc.Expr) Error!okc.Val.Typed {
    switch (expr.kind) {
        .method => unreachable,
        .deref => |deref| return self.genDeref(deref.expr),
        .neg => |neg| return self.genNeg(neg.expr),
        .notb => |notb| return self.genNotb(notb.expr),
        .ptr => |ptr| return self.genPtr(ptr.expr),
        .subslice => |subslice| return self.genSubslice(subslice.*),
        .sizeof => |typ| return self.genSizeof(typ),
        .array => |array| return self.genArray(array),
        .struc => |struc| return self.genStructExpr(struc),
        .int => |int| return genInt(int),
        .str => |str| return self.genStr(str),
        .vari => |vari| return self.genVar(vari),
        .char => |char| return genChar(char),
        .bool => |boo| return genBool(boo),
        .undef => |undef| return genUndef(undef),
        .call => |call| return self.genCall(call.*),
        .binary => |binary| return self.genBinaryExpr(binary.*),
        .field => |field| return self.genField(field.*),
        .named_struc => |struc| return self.genNamedStructExpr(struc),
        .elem => |elem| return self.genElem(elem.*),
    }
}

fn genSizeof(self: *@This(), typ: okc.Typ) !okc.Val.Typed {
    const resolved = try typ.resolve(self.resolve_map, self.arena);
    const layout = try self.getLayout(resolved);
    return .{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = layout.size },
    };
}

fn getLayout(self: *@This(), typ: okc.Typ) !okc.Layout {
    switch (typ) {
        .prime => |prime| return prime.getLayout(),
        .array => |array| {
            const inner = try self.getLayout(array.typ.*);
            return .{
                .size = inner.size * array.len,
                .alig = inner.alig,
            };
        },
        .fun, .ptr => return .new(8, 8),
        .slice => return .new(16, 8),
        .name => |name| {
            try self.genStruct(name);
            return self.structs.get(name).?.layout;
        },
        .loc_name => |located| {
            try self.genStruct(located.bare);
            return self.structs.get(located.bare).?.layout;
        },
        .any, .err, .int, .lazy => unreachable,
    }
}

fn genArray(self: *@This(), array: okc.Expr.Array) !okc.Val.Typed {
    var res = okc.Val.Typed{
        .typ = try array.typ.solve(self.arena),
        .bare = .undef,
    };
    for (array.exprs, 0..) |expr, i| {
        const typ_val = try self.genExpr(expr);
        try self.genIV(&res, typ_val, i);
    }
    return res;
}

fn genNeg(self: *@This(), expr: okc.Expr) !okc.Val.Typed {
    const val = try self.genExpr(expr);
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{d} = sub {f} 0, {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = val.typ }, val.bare },
    );
    return .{
        .typ = val.typ,
        .bare = .{ .tmp = tmp },
    };
}

fn genDerefRef(self: *@This(), expr: okc.Expr) !okc.Val.Ref {
    const val = try self.genExpr(expr);
    return .{
        .inner_typ = val.typ.ptr.typ.*,
        .val = val.bare,
    };
}

fn genDeref(self: *@This(), deref: okc.Expr) !okc.Val.Typed {
    const ref = try self.genDerefRef(deref);
    return self.loadTypVal(ref);
}

fn loadTypVal(self: *@This(), ref: okc.Val.Ref) !okc.Val.Typed {
    const tmp = try self.load(ref);
    return .{
        .typ = ref.inner_typ,
        .bare = .{ .tmp = tmp },
    };
}

fn genNotb(self: *@This(), expr: okc.Expr) !okc.Val.Typed {
    const typ_val = try self.genExpr(expr);
    const tmp = self.newTmp();
    try self.print("\n  %t{d} = xor {f}, -1", .{ tmp, typ_val });
    return .{
        .typ = typ_val.typ,
        .bare = .{ .tmp = tmp },
    };
}

fn genPtr(self: *@This(), expr: okc.Expr) !okc.Val.Typed {
    const ref = try self.genExprRef(expr);
    return ref.toPtrTypVal(self.arena);
}

fn genUndef(undef: okc.Expr.Undef) !okc.Val.Typed {
    return .{ .typ = undef.typ, .bare = .undef };
}

fn genFieldRef(self: *@This(), field: okc.Expr.Field) !okc.Val.Ref {
    var vari = try self.genExprRef(field.expr);
    if (vari.inner_typ == .ptr) {
        const tmp = try self.load(vari);
        vari = .{
            .inner_typ = vari.inner_typ.ptr.typ.*,
            .val = .{ .tmp = tmp },
        };
    }
    if (vari.inner_typ == .array) {
        std.debug.assert(std.mem.eql(u8, field.name, "len"));
        return self.toStack(.{
            .typ = .{ .prime = .u64 },
            .bare = .{ .int = vari.inner_typ.array.len },
        });
    }
    const info = self.getFieldInfo(vari.inner_typ, field.name);
    const tmp = try self.genGEPIB(vari, .int(info.index));
    return .{
        .inner_typ = info.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genField(self: *@This(), field: okc.Expr.Field) !okc.Val.Typed {
    const ref = try self.genFieldRef(field);
    return self.loadTypVal(ref);
}

fn genElemExprRef(self: *@This(), elem: okc.Expr.Elem) !okc.Val.Ref {
    const ref = try self.genExprRef(elem.expr);
    const index = try self.genExpr(elem.index);
    return self.genElemRef(ref, index);
}

fn genElemRef(self: *@This(), from: okc.Val.Ref, index: okc.Val.Typed) !okc.Val.Ref {
    switch (from.inner_typ) {
        .array => {
            const tmp = try self.genGEPIB(from, index);
            return .{
                .inner_typ = from.inner_typ.array.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        .slice => |slice| {
            const ptrptr = try self.genGEPIB(from, .int(0));
            const ptr = try self.load(.{
                .inner_typ = .{ .ptr = .{
                    .typ = slice.typ,
                    .mutable = false,
                } },
                .val = .{ .tmp = ptrptr },
            });
            const tmp = try self.genGEP(slice.typ.*, ptr, index);
            return .{
                .inner_typ = slice.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        else => unreachable,
    }
}

fn genGEP(self: *@This(), typ: okc.Typ, ptr: u32, index: okc.Val.Typed) !u32 {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = getelementptr {f}, ptr %t{}, {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = typ }, ptr, index },
    );
    return tmp;
}

fn genGEPIB(self: *@This(), ref: okc.Val.Ref, index: okc.Val.Typed) !u32 {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = getelementptr inbounds {f}, ptr {f}, i32 0, {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = ref.inner_typ }, ref.val, index },
    );
    return tmp;
}

fn genElem(self: *@This(), elem: okc.Expr.Elem) !okc.Val.Typed {
    const ref = try self.genElemExprRef(elem);
    return self.loadTypVal(ref);
}

fn genSubslice(self: *@This(), subslice: okc.Expr.Subslice) !okc.Val.Typed {
    const ref = try self.genExprRef(subslice.expr);
    const start = try self.genExpr(subslice.start);
    const end = try self.genExpr(subslice.end);
    const ptr_ref = try self.genElemRef(ref, start);
    const ptr = try ptr_ref.toPtrTypVal(self.arena);
    const len = try self.genBinary(.sub, start.typ, end.bare, start.bare);
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = try okc.Typ.memo.box(ptr_ref.inner_typ, self.arena),
            .mutable = false,
        } },
        .bare = .undef,
    };
    try self.genIV(&res, ptr, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .bare = .{ .tmp = len },
    }, 1);
    return res;
}

fn genExprRef(self: *@This(), expr: okc.Expr) Error!okc.Val.Ref {
    switch (expr.kind) {
        .vari => |name| return self.genVarRef(name),
        .field => |field| return self.genFieldRef(field.*),
        .elem => |elem| return self.genElemExprRef(elem.*),
        .deref => |deref| return self.genDerefRef(deref.expr),
        .subslice,
        .sizeof,
        .call,
        .method,
        .binary,
        .named_struc,
        .int,
        .str,
        .char,
        .undef,
        .bool,
        .struc,
        .array,
        .ptr,
        .neg,
        .notb,
        => {
            const typ_val = try self.genExpr(expr);
            return self.toStack(typ_val);
        },
    }
}

fn load(self: *@This(), vari: okc.Val.Ref) !u32 {
    const res = self.newTmp();
    try self.print(
        "\n  %t{} = load {f}, ptr {f}",
        .{ res, okc.Typ.LLPrinter{ .typ = vari.inner_typ }, vari.val },
    );
    return res;
}

fn genInt(int: okc.Expr.Int) okc.Val.Typed {
    return .{
        .typ = int.typ.normalise(),
        .bare = .{ .int = int.val },
    };
}

fn genChar(char: u8) okc.Val.Typed {
    return .{
        .typ = .{ .prime = .u8 },
        .bare = .{ .int = char },
    };
}

fn genBool(boo: bool) okc.Val.Typed {
    return .{
        .typ = .{ .prime = .bool },
        .bare = .{ .int = @intFromBool(boo) },
    };
}

fn genStr(self: *@This(), str: []const u8) !okc.Val.Typed {
    const info = try self.genStrDecl(str);
    const ptr_u8 = try okc.Typ.memo.box(.{ .prime = .u8 }, self.arena);
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .bare = .undef,
    };
    try self.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .bare = .{ .str = info.tmp },
    }, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = info.len },
    }, 1);
    return res;
}

fn genStructExpr(self: *@This(), struc: okc.Expr.Struct) !okc.Val.Typed {
    if (struc.typ.getName()) |typ_name| {
        try self.genStruct(typ_name);
    }
    var res = okc.Val.Typed{
        .typ = struc.typ,
        .bare = .undef,
    };
    if (struc.typ.getName()) |typ_name| {
        for (self.structs.get(typ_name).?.default_fields) |field| {
            const typ_val = try self.genExpr(field.expr);
            try self.genIV(&res, typ_val, field.index);
        }
    }
    for (struc.fields) |field| {
        const typ_val = try self.genExpr(field.expr);
        const info = self.getFieldInfo(struc.typ, field.name);
        try self.genIV(&res, typ_val, info.index);
    }
    return res;
}

fn genIV(self: *@This(), to: *okc.Val.Typed, typ_val: okc.Val.Typed, index: u64) !void {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = insertvalue {f}, {f}, {d}",
        .{ tmp, to, typ_val, index },
    );
    to.bare = .{ .tmp = tmp };
}

fn genNamedStructExpr(self: *@This(), named: okc.Expr.Struct.Named) !okc.Val.Typed {
    return self.genStructExpr(named.bare);
}

fn genBinaryExpr(self: *@This(), binary: okc.Expr.Binary) !okc.Val.Typed {
    const left = try self.genExpr(binary.left);
    const right = try self.genExpr(binary.right);
    const tmp = try self.genBinary(binary.kind, left.typ, left.bare, right.bare);
    return .{
        .typ = binOpRetTyp(binary.kind, left.typ),
        .bare = .{ .tmp = tmp },
    };
}

fn genBinary(self: *@This(), kind: okc.Expr.Binary.Kind, typ: okc.Typ, a: okc.Val, b: okc.Val) !u32 {
    const tmp = self.newTmp();
    try self.print("\n  %t{} = ", .{tmp});
    try self.genBinOp(kind);
    try self.print(" {f} {f}, {f}", .{ okc.Typ.LLPrinter{ .typ = typ }, a, b });
    return tmp;
}

fn binOpRetTyp(kind: okc.Expr.Binary.Kind, child_typ: okc.Typ) okc.Typ {
    return switch (kind.getClass()) {
        .arith => child_typ,
        .bool => .{ .prime = .bool },
    };
}

fn genBinOp(self: *@This(), kind: okc.Expr.Binary.Kind) !void {
    switch (kind) {
        .moreq => try self.print("icmp sge", .{}),
        .orb => try self.print("or", .{}),
        .andb => try self.print("and", .{}),
        .add => try self.print("add", .{}),
        .sub => try self.print("sub", .{}),
        .mul => try self.print("mul", .{}),
        .div => try self.print("sdiv", .{}),
        .rem => try self.print("srem", .{}),
        .equ => try self.print("icmp eq", .{}),
        .les => try self.print("icmp slt", .{}),
        .neq => try self.print("icmp ne", .{}),
    }
}

fn genFunPtr(self: *@This(), fun_name: []const u8, fun_meta: okc.Expr.FunMeta) !okc.Val.Typed {
    var name = okc.Typ.Name{
        .name = fun_name,
        .generics = fun_meta.generics,
    };
    if (self.items.get(fun_name).?.kind == .ext_fun) {
        name.generics = &.{};
    }
    const typ: okc.Typ = .{ .fun = fun_meta.typ.fun };
    const solved = try typ.solve(self.arena);
    try self.fun_queue.append(self.gpa, .{
        .name = name,
        .fun = solved.fun,
    });
    return .{
        .typ = solved,
        .bare = .{ .global = name },
    };
}

fn genVarRef(self: *@This(), vari: okc.Expr.Var) !okc.Val.Ref {
    if (vari.fun_meta) |fun_meta| {
        return self.toStack(try self.genFunPtr(vari.name, fun_meta));
    }
    return self.vars.get(vari.name) orelse {
        try self.genConst(vari.name);
        return .{
            .inner_typ = self.consts.get(vari.name).?,
            .val = .{ .global = .{ .name = vari.name } },
        };
    };
}

fn genConst(self: *@This(), name: []const u8) !void {
    const was = try self.generated.getOrPut(.{ .name = name });
    if (was.found_existing) {
        return;
    }
    const expr = self.items.get(name).?.kind.constant.declare.expr;
    const buffer = self.buffer.?;
    self.buffer = .empty;
    defer {
        if (self.buffer) |*buf| {
            buf.deinit(self.gpa);
        }
        self.buffer = buffer;
    }

    try self.print("\n@{s} = private unnamed_addr constant ", .{name});
    const typ = try self.genConstExpr(expr);
    try self.consts.put(name, typ);
    var written = self.buffer.?;
    self.buffer = null;
    defer written.deinit(self.gpa);
    try self.print("{s}", .{written.items});
}

fn genConstExpr(self: *@This(), expr: okc.Expr) Error!okc.Typ {
    switch (expr.kind) {
        .str => |str| return self.genConstStr(str),
        .named_struc => |named| return self.genConstStruc(named.bare),
        .struc => |struc| return self.genConstStruc(struc),
        .array => |array| return self.genConstArray(array),
        else => unreachable,
    }
}

fn genConstArray(self: *@This(), array: okc.Expr.Array) !okc.Typ {
    try self.print("{f} [", .{okc.Typ.LLPrinter{ .typ = array.typ }});
    if (array.exprs.len != 0) {
        try self.print("\n  ", .{});
        _ = try self.genConstExpr(array.exprs[0]);
        for (array.exprs[1..]) |expr| {
            try self.print(",\n  ", .{});
            _ = try self.genConstExpr(expr);
        }
    }
    try self.print("\n]", .{});
    return array.typ;
}

fn genConstStruc(self: *@This(), struc: okc.Expr.Struct) !okc.Typ {
    if (struc.typ.getName()) |typ_name| {
        try self.genStruct(typ_name);
    }
    try self.print("{f} {{", .{okc.Typ.LLPrinter{ .typ = struc.typ }});
    if (struc.fields.len != 0) {
        const fields = try self.gpa.alloc(okc.Expr, struc.fields.len);
        defer self.gpa.free(fields);
        if (struc.typ.getName()) |typ_name| {
            for (self.structs.get(typ_name).?.default_fields) |field| {
                fields[field.index] = field.expr;
            }
        }
        for (struc.fields) |field| {
            const info = self.getFieldInfo(struc.typ, field.name);
            fields[info.index] = field.expr;
        }
        try self.print("\n  ", .{});
        _ = try self.genConstExpr(fields[0]);
        for (fields[1..]) |expr| {
            try self.print(",\n  ", .{});
            _ = try self.genConstExpr(expr);
        }
    }
    try self.print("\n}}", .{});
    return struc.typ;
}

fn getFieldInfo(self: *@This(), typ: okc.Typ, name: []const u8) okc.Item.Struct.Field.GenInfo {
    return if (typ.getName()) |typ_name|
        self.structs.get(typ_name).?.fields.get(name).?
    else if (std.mem.eql(u8, name, "ptr")) .{
        .typ = .{ .ptr = .{
            .typ = typ.slice.typ,
            .mutable = typ.slice.mutable,
        } },
        .index = 0,
    } else .{
        .typ = .{ .prime = .u64 },
        .index = 1,
    };
}

fn genConstStr(self: *@This(), str: []const u8) !okc.Typ {
    const info = try self.genStrDecl(str);
    try self.print("%\"[]\" {{ ptr @.s{d}, i64 {d} }}", .{ info.tmp, info.len });
    return .{ .slice = .{
        .typ = try okc.Typ.memo.box(.{ .prime = .u8 }, self.arena),
        .mutable = false,
    } };
}

fn genVar(self: *@This(), vari: okc.Expr.Var) !okc.Val.Typed {
    if (vari.fun_meta) |fun_meta| {
        return self.genFunPtr(vari.name, fun_meta);
    }
    const ref = try self.genVarRef(vari);
    return self.loadTypVal(ref);
}

fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
    if (self.buffer) |*buffer| {
        try buffer.print(self.gpa, fmt, args);
    } else {
        try self.writer.interface.print(fmt, args);
    }
}

const Error = error{ WriteFailed, OutOfMemory };

fn deinit(self: *@This()) void {
    self.items.deinit();
    self.vars.deinit();
    self.file.close(self.io);
    self.loop_ends.deinit(self.gpa);
    self.fun_queue.deinit(self.gpa);
    self.generated.deinit();
    self.resolve_map.deinit();
    self.consts.deinit();
    self.deinitStructs();
    self.extra_buffer.deinit(self.gpa);
    self.* = undefined;
}

fn deinitStructs(self: *@This()) void {
    var iter = self.structs.valueIterator();
    while (iter.next()) |info| {
        info.fields.deinit();
        self.gpa.free(info.default_fields);
    }
    self.structs.deinit();
}
