const std = @import("std");

const Ast = @import("Ast/mod.zig");
const HashMap = @import("hash_map.zig").HashMap;
const memo = @import("memo.zig");
const Typ = @import("typ/mod.zig").Typ;
const Name = Typ.Name;

const Resolver = @import("resolver.zig").Resolver;

const Self = @This();
io: std.Io,
gpa: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
buffer: ?std.ArrayList(u8) = null,
extra_buffer: std.ArrayList(u8) = .empty,
typ_mem: *memo.Memo(Typ),
items: std.StringHashMap(*const Ast.Item),
structs: HashMap(Name, Struct),
consts: std.StringHashMap(Typ),
vars: std.StringHashMap(Ref),
loop_ends: std.ArrayList(u32) = .empty,
fun_queue: std.ArrayList(FunReq) = .empty,
generated: HashMap(Name, void),
resolve_map: std.StringHashMap(Typ),
next_tmp: u32 = 0,

const FunReq = struct {
    name: Name,
    fun: Typ.Fun,
};

pub fn init(
    io: std.Io,
    gpa: std.mem.Allocator,
    typ_mem: *memo.Memo(Typ),
    items: std.StringHashMap(*const Ast.Item),
    write_buf: []u8,
    path: []const u8,
) error{ OutOfMemory, Handled }!Self {
    const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch {
        std.log.err("failed to create `{s}`", .{path});
        return error.Handled;
    };
    return .{
        .io = io,
        .gpa = gpa,
        .typ_mem = typ_mem,
        .file = file,
        .items = items,
        .resolve_map = .init(gpa),
        .writer = file.writer(io, write_buf),
        .vars = .init(gpa),
        .structs = .init(gpa),
        .consts = .init(gpa),
        .generated = .init(gpa),
    };
}

pub fn run(self: *Self) error{ WriteFailed, OutOfMemory }!void {
    defer self.deinit();
    try self.genAll();
    try self.writer.interface.flush();
}

fn genAll(self: *Self) !void {
    try self.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    try self.genSliceDecl();
    try self.genFunNamed(.{
        .name = .{ .name = "main" },
        .fun = .{
            .params = &.{},
            .ret_typ = try self.typ_mem.box(.{ .prime = .i32 }),
        },
    });
    while (self.fun_queue.items.len != 0) {
        const req = self.fun_queue.pop().?;
        try self.genFunNamed(req);
    }
    try self.print("\n", .{});
}

fn genFunNamed(self: *Self, req: FunReq) !void {
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

fn genSliceDecl(self: *Self) !void {
    try self.print("\n%\"[]\" = type {{ ptr, i64 }}", .{});
}

fn genExtFun(self: *Self, name: []const u8, ext_fun: Ast.Item.Fun.Extern) !void {
    try self.print("\ndeclare {f} @{s}(", .{
        LlvmTyp{ .inner = ext_fun.header.ret_typ },
        name,
    });
    if (ext_fun.header.params.len != 0) {
        try self.print("{f}", .{LlvmTyp{ .inner = ext_fun.header.params[0].typ }});
        for (ext_fun.header.params[1..]) |param| {
            try self.print(", {f}", .{LlvmTyp{ .inner = param.typ }});
        }
    }
    try self.print(")", .{});
}

fn genStrDecl(self: *Self, str: []const u8) !Str {
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

fn unescape(gpa: std.mem.Allocator, str: []const u8) !Unescaped {
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
    self: *Self,
    name: Name,
    fun: Ast.Item.Fun,
    fun_typ: Typ.Fun,
) !void {
    self.buffer = self.extra_buffer;
    try self.print(
        "\ndefine {f} @\"{f}\"(",
        .{ LlvmTyp{ .inner = fun_typ.ret_typ.* }, name },
    );
    var param_typ_vals = try self.gpa.alloc(TypVal, fun.header.params.len);
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
    for (fun.body) |stmt| {
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

fn genStruct(self: *Self, name: Name) Error!void {
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
    var fields = std.StringHashMap(Field).init(self.gpa);
    var default_fields_vec = std.ArrayList(DefaultField).empty;
    try self.print("\n%\"{f}\" = type {{", .{name});
    const struc = self.items.get(name.name).?.kind.struc;
    var resolve_map: std.StringHashMap(Typ) = .init(self.gpa);
    defer resolve_map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolve_map.put(generic.name, typ);
    }
    var struct_layout = Layout{ .size = 0, .alig = 1 };
    const field_typs = try self.gpa.alloc(Typ, struc.fields.len);
    defer self.gpa.free(field_typs);
    for (field_typs, struc.fields, 0..) |*typ, field, i| {
        typ.* = try field.typ.resolve(self.makeResolver(resolve_map));
        const layout = try self.getLayout(typ.*);
        appendLayout(&struct_layout, layout);
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
        try self.print("\n  {f}", .{LlvmTyp{ .inner = field_typs[0] }});
        for (field_typs[1..]) |typ| {
            try self.print(",\n  {f}", .{LlvmTyp{ .inner = typ }});
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

fn genParam(self: *Self, typ: Typ) !TypVal {
    const tmp = self.newTmp();
    try self.print("{f} %t{}", .{ LlvmTyp{ .inner = typ }, tmp });
    return .{ .typ = typ, .val = .{ .tmp = tmp } };
}

fn genStmt(self: *Self, stmt: Ast.Stmt) Error!void {
    switch (stmt.kind) {
        .for_range => |forr| try self.genForRange(forr),
        .forr => |forr| try self.genFor(forr),
        .op_assign => |op_assign| try self.genOpAssign(op_assign),
        .unre => try self.genUnreachable(),
        .ret => |ret| try self.genRet(ret),
        .expr => |expr| _ = try self.genExpr(expr),
        .declare => |named| try self.genDeclare(named.name, named.declare),
        .assign => |assign| try self.genAssign(assign),
        .iff => |iff| try self.genIf(iff),
        .whi => |whi| try self.genWhile(whi),
        .ignore => |ignore| try self.genIgnore(ignore),
        .brek => try self.genBreak(),
    }
}

fn genUnreachable(self: *Self) !void {
    try self.print("\n  unreachable", .{});
}

fn genIgnore(self: *Self, ignore: Ast.Stmt.Ignore) !void {
    _ = try self.genExpr(ignore.expr);
}

fn genBreak(self: *Self) !void {
    const label = self.newTmp();
    try self.uncond(self.loop_ends.getLast(), label);
}

fn genWhile(self: *Self, whi: Ast.Stmt.While) !void {
    const condition_label = self.newTmp();
    try self.uncond(condition_label, condition_label);
    try self.genBranch(whi.branch, condition_label, true);
}

fn genForRange(self: *Self, forr: Ast.Stmt.ForRange) !void {
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
    const inew = try self.genBinary(.add, ival.typ, ival.val, .{ .int = 1 });
    try self.storeInto(self.vars.get(forr.vari).?.val, .{ .typ = ival.typ, .val = .{ .tmp = inew } });
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i != end
    const ival_ = try self.loadTypVal(self.vars.get(forr.vari).?);
    const at_end = try self.genBinary(.neq, ival.typ, ival_.val, end.val);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = at_end }, body_label, end_label);
    // <body>
    for (forr.body) |stmt| {
        try self.genStmt(stmt);
    }
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

fn genFor(self: *Self, forr: Ast.Stmt.For) !void {
    const slice = try self.genExprRef(forr.expr);
    // int i = 0
    const iref = try self.toStack(.{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = 0 },
    });
    // goto cond
    // start:
    const start_label = self.newTmp();
    const cond_label = self.newTmp();
    try self.uncond(cond_label, start_label);
    // i++
    const ival = try self.loadTypVal(iref);
    const inew = try self.genBinary(.add, ival.typ, ival.val, .{ .int = 1 });
    try self.storeInto(iref.val, .{ .typ = ival.typ, .val = .{ .tmp = inew } });
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i < .len
    const ival_ = try self.loadTypVal(iref);
    const len = try self.genField(.{
        .expr = forr.expr,
        .name = "len",
    });
    const less = try self.genBinary(.les, ival.typ, ival_.val, len.val);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = less }, body_label, end_label);
    // var = slice[i]
    const elem = try self.genElemRef(slice, ival_);
    try self.vars.put(forr.vari, elem);
    // <body>
    for (forr.body) |stmt| {
        try self.genStmt(stmt);
    }
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

fn cond(
    self: *Self,
    condition: Val,
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

fn uncond(self: *Self, to: u32, next: u32) !void {
    try self.print(
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
}

fn genIf(self: *Self, iff: Ast.Stmt.If) !void {
    const end_label = self.newTmp();
    try self.genBranch(iff.branch, end_label, false);
    for (iff.else_ifs) |branch| {
        try self.genBranch(branch, end_label, false);
    }
    for (iff.else_branch) |stmt| {
        try self.genStmt(stmt);
    }
    try self.uncond(end_label, end_label);
}

fn genBranch(self: *Self, branch: Ast.Stmt.Branch, end_label: u32, loop: bool) !void {
    const condition = try self.genExpr(branch.condition);
    const then_label = self.newTmp();
    const else_label = self.newTmp();
    if (loop) {
        try self.loop_ends.append(self.gpa, else_label);
    }
    try self.cond(condition.val, then_label, else_label);
    for (branch.body) |stmt| {
        try self.genStmt(stmt);
    }
    try self.uncond(end_label, else_label);
    if (loop) {
        _ = self.loop_ends.pop();
    }
}

fn genOpAssign(self: *Self, op_assign: Ast.Stmt.OpAssign) !void {
    const vari = try self.genExprRef(op_assign.left);
    const typ_val = try self.genBinaryExpr(.{
        .left = op_assign.left,
        .kind = op_assign.kind,
        .right = op_assign.right,
    });
    try self.storeInto(vari.val, typ_val);
}

fn genAssign(self: *Self, assign: Ast.Stmt.Assign) !void {
    const vari = try self.genExprRef(assign.left);
    const typ_val = try self.genExpr(assign.expr);
    try self.storeInto(vari.val, typ_val);
}

fn genDeclare(self: *Self, name: []const u8, declare: Ast.Stmt.Declare) !void {
    const typ_val = try self.genExpr(declare.expr);
    const vari = try self.toStack(typ_val);
    try self.vars.put(name, vari);
}

fn toStack(self: *Self, typ_val: TypVal) !Ref {
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

fn genAlloca(self: *Self, tmp: u32, typ: Typ) !void {
    const buffer = self.buffer;
    // so that all allocs are in entry block
    self.buffer = self.extra_buffer;
    defer {
        self.extra_buffer = self.buffer.?;
        self.buffer = buffer;
    }
    try self.print("\n  %t{} = alloca {f}", .{ tmp, LlvmTyp{ .inner = typ } });
}

fn storeInto(self: *Self, val: Val, typ_val: TypVal) !void {
    try self.print("\n  store {f}, ptr {f}", .{ typ_val, val });
}

fn genCall(self: *Self, call: Ast.Expr.Call) !TypVal {
    const typ_val = try self.genExpr(call.expr);
    var arg_typ_vals = try self.gpa.alloc(TypVal, call.args.len);
    defer self.gpa.free(arg_typ_vals);
    for (arg_typ_vals, call.args, typ_val.typ.fun.params) |*target, arg, param| {
        target.* = try self.genExpr(arg);
        if (param == .slice and target.typ == .ptr) {
            target.* = try self.genArrayToSlice(target.typ.ptr.typ.array, target.val);
        }
    }
    const ret_tmp = self.newTmp();
    if (typ_val.typ.fun.ret_typ.* != .prime or typ_val.typ.fun.ret_typ.prime != .void) {
        try self.print("\n  %t{} = ", .{ret_tmp});
    } else {
        try self.print("\n  ", .{});
    }
    try self.print("call {f} {f} (", .{
        LlvmTyp{ .inner = typ_val.typ.fun.ret_typ.* },
        typ_val.val,
    });
    if (call.args.len != 0) {
        try self.print("{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try self.print(", {f}", .{val});
        }
    }
    try self.print(")", .{});
    return .{
        .val = .{ .tmp = ret_tmp },
        .typ = typ_val.typ.fun.ret_typ.*,
    };
}

fn genArrayToSlice(self: *Self, array: Typ.Array, val: Val) !TypVal {
    var res = TypVal{
        .typ = .{ .slice = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .val = .undef,
    };
    try self.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .val = val,
    }, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = array.len },
    }, 1);
    return res;
}

fn newTmp(self: *Self) u32 {
    self.next_tmp += 1;
    return self.next_tmp - 1;
}

fn genRet(self: *Self, ret: Ast.Stmt.Return) !void {
    if (ret.expr) |expr| {
        const val = try self.genExpr(expr);
        try self.print("\n  ret {f}", .{val});
    } else {
        try self.print("\n  ret void", .{});
    }
}

fn genExpr(self: *Self, expr: Ast.Expr) Error!TypVal {
    switch (expr.kind) {
        .method => unreachable,
        .subslice => |subslice| return self.genSubslice(subslice.*),
        .sizeof => |typ| return self.genSizeof(typ),
        .array => |array| return self.genArray(array),
        .unary => |unary| return self.genUnary(unary.*),
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

fn genSizeof(self: *Self, typ: Typ) !TypVal {
    const resolved = try typ.resolve(self.funResolver());
    const layout = try self.getLayout(resolved);
    return .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = layout.size },
    };
}

fn funResolver(self: Self) Resolver(Typ) {
    return .{
        .map = self.resolve_map,
        .mem = self.typ_mem,
    };
}

fn makeResolver(self: Self, map: std.StringHashMap(Typ)) Resolver(Typ) {
    return .{ .map = map, .mem = self.typ_mem };
}

fn getLayout(self: *Self, typ: Typ) !Layout {
    switch (typ) {
        .prime => |prime| return primeLayout(prime),
        .array => |array| {
            const inner = try self.getLayout(array.typ.*);
            return .{
                .size = inner.size * array.len,
                .alig = inner.alig,
            };
        },
        .fun, .ptr => return .make(8, 8),
        .slice => return .make(16, 8),
        .name => |name| {
            try self.genStruct(name);
            return self.structs.get(name).?.layout;
        },
        .loc_name => |located| {
            try self.genStruct(located.name);
            return self.structs.get(located.name).?.layout;
        },
        .any, .err, .int, .lazy => unreachable,
    }
}

fn genArray(self: *Self, array: Ast.Expr.Array) !TypVal {
    var res = TypVal{
        .typ = array.typ,
        .val = .undef,
    };
    for (array.exprs, 0..) |expr, i| {
        const typ_val = try self.genExpr(expr);
        try self.genIV(&res, typ_val, i);
    }
    return res;
}

fn genUnary(self: *Self, unary: Ast.Expr.Unary) !TypVal {
    switch (unary.kind) {
        .deref => return self.genDeref(unary.expr),
        .notb => return self.genNotb(unary.expr),
        .ptr => return self.genPtr(unary.expr),
        .neg => return self.genNeg(unary.expr),
    }
}

fn genNeg(self: *Self, expr: Ast.Expr) !TypVal {
    const typ_val = try self.genExpr(expr);
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{d} = sub {f} 0, {f}",
        .{ tmp, LlvmTyp{ .inner = typ_val.typ }, typ_val.val },
    );
    return .{
        .typ = typ_val.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genDerefRef(self: *Self, expr: Ast.Expr) !Ref {
    const typ_val = try self.genExpr(expr);
    return .{
        .inner_typ = typ_val.typ.ptr.typ.*,
        .val = typ_val.val,
    };
}

fn genDeref(self: *Self, deref: Ast.Expr) !TypVal {
    const ref = try self.genDerefRef(deref);
    return self.loadTypVal(ref);
}

fn loadTypVal(self: *Self, ref: Ref) !TypVal {
    const tmp = try self.load(ref);
    return .{
        .typ = ref.inner_typ,
        .val = .{ .tmp = tmp },
    };
}

fn genNotb(self: *Self, expr: Ast.Expr) !TypVal {
    const typ_val = try self.genExpr(expr);
    const tmp = self.newTmp();
    try self.print("\n  %t{d} = xor {f}, -1", .{ tmp, typ_val });
    return .{
        .typ = typ_val.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genPtr(self: *Self, expr: Ast.Expr) !TypVal {
    const ref = try self.genExprRef(expr);
    return self.makePtrFromRef(ref);
}

fn makePtrFromRef(self: *Self, ref: Ref) !TypVal {
    return .{
        .typ = .{ .ptr = .{
            .typ = try self.typ_mem.box(ref.inner_typ),
            .mutable = false,
        } },
        .val = ref.val,
    };
}

fn genUndef(undef: Ast.Expr.Undef) !TypVal {
    return .{ .typ = undef.typ, .val = .undef };
}

fn genFieldRef(self: *Self, field: Ast.Expr.Field) !Ref {
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
            .val = .{ .int = vari.inner_typ.array.len },
        });
    }
    const info = self.getFieldInfo(vari.inner_typ, field.name);
    const tmp = try self.genGEPIB(vari, .int(info.index));
    return .{
        .inner_typ = info.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genField(self: *Self, field: Ast.Expr.Field) !TypVal {
    const ref = try self.genFieldRef(field);
    return self.loadTypVal(ref);
}

fn genElemExprRef(self: *Self, elem: Ast.Expr.Elem) !Ref {
    const ref = try self.genExprRef(elem.expr);
    const index = try self.genExpr(elem.index);
    return self.genElemRef(ref, index);
}

fn genElemRef(self: *Self, from: Ref, index: TypVal) !Ref {
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

fn genGEP(self: *Self, typ: Typ, ptr: u32, index: TypVal) !u32 {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = getelementptr {f}, ptr %t{}, {f}",
        .{ tmp, LlvmTyp{ .inner = typ }, ptr, index },
    );
    return tmp;
}

fn genGEPIB(self: *Self, ref: Ref, index: TypVal) !u32 {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = getelementptr inbounds {f}, ptr {f}, i32 0, {f}",
        .{ tmp, LlvmTyp{ .inner = ref.inner_typ }, ref.val, index },
    );
    return tmp;
}

fn genElem(self: *Self, elem: Ast.Expr.Elem) !TypVal {
    const ref = try self.genElemExprRef(elem);
    return self.loadTypVal(ref);
}

fn genSubslice(self: *Self, subslice: Ast.Expr.Subslice) !TypVal {
    const ref = try self.genExprRef(subslice.expr);
    const start = try self.genExpr(subslice.start);
    const end = try self.genExpr(subslice.end);
    const ptr_ref = try self.genElemRef(ref, start);
    const ptr = try self.makePtrFromRef(ptr_ref);
    const len = try self.genBinary(.sub, start.typ, end.val, start.val);
    var res = TypVal{ .typ = .{ .slice = .{
        .typ = try self.typ_mem.box(ptr_ref.inner_typ),
        .mutable = false,
    } }, .val = .undef };
    try self.genIV(&res, ptr, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .tmp = len },
    }, 1);
    return res;
}

fn genExprRef(self: *Self, expr: Ast.Expr) Error!Ref {
    switch (expr.kind) {
        .unary => |unary| return self.genUnaryRef(unary.*),
        .vari => |name| return self.genVarRef(name),
        .field => |field| return self.genFieldRef(field.*),
        .elem => |elem| return self.genElemExprRef(elem.*),
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
        => {
            const typ_val = try self.genExpr(expr);
            return self.toStack(typ_val);
        },
    }
}

fn genUnaryRef(self: *Self, unary: Ast.Expr.Unary) !Ref {
    switch (unary.kind) {
        .deref => return self.genDerefRef(unary.expr),
        .notb, .ptr, .neg => {
            const typ_val = try self.genUnary(unary);
            const vari = try self.toStack(typ_val);
            return vari;
        },
    }
}

fn load(self: *Self, vari: Ref) !u32 {
    const to = self.newTmp();
    try self.print(
        "\n  %t{} = load {f}, ptr {f}",
        .{ to, LlvmTyp{ .inner = vari.inner_typ }, vari.val },
    );
    return to;
}

fn genInt(int: Ast.Expr.Int) TypVal {
    return .{
        .typ = int.typ,
        .val = .{ .int = int.val },
    };
}

fn genChar(char: u8) TypVal {
    return .{
        .typ = .{ .prime = .u8 },
        .val = .{ .int = char },
    };
}

fn genBool(boo: bool) TypVal {
    return .{
        .typ = .{ .prime = .bool },
        .val = .{ .int = @intFromBool(boo) },
    };
}

fn genStr(self: *Self, str: []const u8) !TypVal {
    const info = try self.genStrDecl(str);
    const ptr_u8 = try self.typ_mem.box(.{ .prime = .u8 });
    var res = TypVal{
        .typ = .{ .slice = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .val = .undef,
    };
    try self.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .val = .{ .str = info.tmp },
    }, 0);
    try self.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = info.len },
    }, 1);
    return res;
}

fn genStructExpr(self: *Self, struc: Ast.Expr.Struct) !TypVal {
    if (struc.typ.getName()) |typ_name| {
        try self.genStruct(typ_name);
    }
    var res = TypVal{
        .typ = struc.typ,
        .val = .undef,
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

fn genIV(self: *Self, to: *TypVal, typ_val: TypVal, index: u64) !void {
    const tmp = self.newTmp();
    try self.print(
        "\n  %t{} = insertvalue {f}, {f}, {d}",
        .{ tmp, to, typ_val, index },
    );
    to.val = .{ .tmp = tmp };
}

fn genNamedStructExpr(self: *Self, named: Ast.Expr.Struct.Named) !TypVal {
    return self.genStructExpr(named.struc);
}

fn genBinaryExpr(self: *Self, binary: Ast.Expr.Binary) !TypVal {
    const left = try self.genExpr(binary.left);
    const right = try self.genExpr(binary.right);
    const tmp = try self.genBinary(binary.kind, left.typ, left.val, right.val);
    return .{
        .typ = binOpRetTyp(binary.kind, left.typ),
        .val = .{ .tmp = tmp },
    };
}

fn genBinary(self: *Self, kind: Ast.Expr.Binary.Kind, typ: Typ, a: Val, b: Val) !u32 {
    const tmp = self.newTmp();
    try self.print("\n  %t{} = ", .{tmp});
    try self.genBinOp(kind);
    try self.print(" {f} {f}, {f}", .{ LlvmTyp{ .inner = typ }, a, b });
    return tmp;
}

fn binOpRetTyp(kind: Ast.Expr.Binary.Kind, child_typ: Typ) Typ {
    return switch (kind.getClass()) {
        .arith => child_typ,
        .bool => .{ .prime = .bool },
    };
}

fn genBinOp(self: *Self, kind: Ast.Expr.Binary.Kind) !void {
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

fn genFunPtr(self: *Self, fun_name: []const u8, fun_meta: Ast.Expr.FunMeta) !TypVal {
    var name = Name{
        .name = fun_name,
        .generics = fun_meta.generics,
    };
    if (self.items.get(fun_name).?.kind == .ext_fun) {
        name.generics = &.{};
    }
    try self.fun_queue.append(self.gpa, .{
        .name = name,
        .fun = fun_meta.typ.fun,
    });
    return .{
        .typ = .{ .fun = fun_meta.typ.fun },
        .val = .{ .global = name },
    };
}

fn genVarRef(self: *Self, vari: Ast.Expr.Var) !Ref {
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

fn genConst(self: *Self, name: []const u8) !void {
    const was = try self.generated.getOrPut(.{ .name = name });
    if (was.found_existing) {
        return;
    }
    const expr = self.items.get(name).?.kind.constant.expr;
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

fn genConstExpr(self: *Self, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .str => |str| return self.genConstStr(str),
        .named_struc => |named| return self.genConstStruc(named.struc),
        .struc => |struc| return self.genConstStruc(struc),
        .array => |array| return self.genConstArray(array),
        else => unreachable,
    }
}

fn genConstArray(self: *Self, array: Ast.Expr.Array) !Typ {
    try self.print("{f} [", .{LlvmTyp{ .inner = array.typ }});
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

fn genConstStruc(self: *Self, struc: Ast.Expr.Struct) !Typ {
    if (struc.typ.getName()) |typ_name| {
        try self.genStruct(typ_name);
    }
    try self.print("{f} {{", .{LlvmTyp{ .inner = struc.typ }});
    if (struc.fields.len != 0) {
        const fields = try self.gpa.alloc(Ast.Expr, struc.fields.len);
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

fn getFieldInfo(self: *Self, typ: Typ, name: []const u8) Field {
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

fn genConstStr(self: *Self, str: []const u8) !Typ {
    const info = try self.genStrDecl(str);
    try self.print("%\"[]\" {{ ptr @.s{d}, i64 {d} }}", .{ info.tmp, info.len });
    return .{ .slice = .{
        .typ = try self.typ_mem.box(.{ .prime = .u8 }),
        .mutable = false,
    } };
}

fn genVar(self: *Self, vari: Ast.Expr.Var) !TypVal {
    if (vari.fun_meta) |fun_meta| {
        return self.genFunPtr(vari.name, fun_meta);
    }
    const ref = try self.genVarRef(vari);
    return self.loadTypVal(ref);
}

fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    if (self.buffer) |*buffer| {
        try buffer.print(self.gpa, fmt, args);
    } else {
        try self.writer.interface.print(fmt, args);
    }
}

const Error = error{ WriteFailed, OutOfMemory };

fn deinit(self: *Self) void {
    self.vars.deinit();
    self.file.close(self.io);
    self.loop_ends.deinit(self.gpa);
    self.fun_queue.deinit(self.gpa);
    self.generated.deinit();
    self.resolve_map.deinit();
    self.items.deinit();
    self.consts.deinit();
    self.deinitStructs();
    self.extra_buffer.deinit(self.gpa);
    self.* = undefined;
}

fn deinitStructs(self: *Self) void {
    var iter = self.structs.valueIterator();
    while (iter.next()) |info| {
        info.fields.deinit();
        self.gpa.free(info.default_fields);
    }
    self.structs.deinit();
}

fn appendLayout(res: *Layout, layout: Layout) void {
    res.alig = @max(res.alig, layout.alig);
    // padding
    if (layout.size % layout.alig != 0) {
        res.size += layout.alig - (res.size % layout.alig);
    }
    res.size += layout.size;
}

fn primeLayout(prime: Typ.Prime) !Layout {
    return switch (prime) {
        .u8, .bool => .make(1, 1),
        .i32, .u32 => .make(4, 4),
        .u64 => .make(8, 8),
        .void => .make(0, 1),
    };
}

const Layout = struct {
    size: u64,
    alig: u64,

    fn make(size: u64, alig: u64) Layout {
        return .{
            .size = size,
            .alig = alig,
        };
    }
};

const DefaultField = struct {
    index: usize,
    expr: Ast.Expr,
};

const Field = struct {
    index: usize,
    typ: Typ,
};

const Struct = struct {
    fields: std.StringHashMap(Field),
    default_fields: []const DefaultField,
    layout: Layout,
};

const Str = struct {
    len: usize,
    tmp: u32,
};

const LlvmTyp = struct {
    inner: Typ,

    pub fn format(typ: LlvmTyp, writer: *std.Io.Writer) !void {
        switch (typ.inner) {
            .prime => |prime| {
                const s = switch (prime) {
                    .u8 => "i8",
                    .i32 => "i32",
                    .u32 => "i32",
                    .u64 => "i64",
                    .bool => "i1",
                    .void => "void",
                };
                try writer.writeAll(s);
            },
            .array => |array| {
                try writer.print("[{} x {f}]", .{
                    array.len,
                    LlvmTyp{ .inner = array.typ.* },
                });
            },
            .slice => try writer.writeAll("%\"[]\""),
            .ptr, .fun => try writer.writeAll("ptr"),
            .name => |name| try writer.print("%\"{f}\"", .{name}),
            .loc_name => |located| try writer.print("%\"{f}\"", .{located.name}),
            .lazy, .any, .int, .err => unreachable,
        }
    }
};

const Unescaped = struct { len: usize, repr: []const u8 };

const TypVal = struct {
    typ: Typ,
    val: Val,

    pub fn format(
        typ_val: TypVal,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{f} {f}", .{ LlvmTyp{ .inner = typ_val.typ }, typ_val.val });
    }

    pub fn int(n: u64) TypVal {
        return .{
            .typ = .{ .prime = .i32 },
            .val = .{ .int = n },
        };
    }
};

const Val = union(enum) {
    int: u64,
    str: usize,
    tmp: u32,
    global: Name,
    undef,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("{d}", .{int}),
            .str => |str| try writer.print("@.s{}", .{str}),
            .tmp => |tmp| try writer.print("%t{}", .{tmp}),
            .global => |name| try writer.print("@\"{f}\"", .{name}),
            .undef => try writer.writeAll("poison"),
        }
    }
};

const Ref = struct {
    val: Val,
    inner_typ: Typ,
};
