const std = @import("std");

const Ast = @import("Ast.zig");
const Typ = Ast.Typ;
const HashMap = @import("hash_map.zig").HashMap;
const Memo = @import("memo.zig").Memo;
const Name = @import("typ_kinds.zig").Name(Typ);
const Resolver = @import("resolver.zig").Resolver(Typ);

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
            .name => try writer.print("%\"{f}\"", .{typ.inner}),
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
    global: []const u8,
    undef,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("{d}", .{int}),
            .str => |str| try writer.print("@.s{}", .{str}),
            .tmp => |tmp| try writer.print("%t{}", .{tmp}),
            .global => |name| try writer.print("@\"{s}\"", .{name}),
            .undef => try writer.writeAll("poison"),
        }
    }
};

const Ref = struct {
    val: Val,
    inner_typ: Typ,
};

const Codegen = @This();

io: std.Io,
gpa: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
buffer: ?std.ArrayList(u8) = null,
extra_buffer: std.ArrayList(u8) = .empty,
typ_memo: *Memo(Ast.Typ),
items: std.StringHashMap(*const Ast.Item),
structs: HashMap(Name, Struct),
consts: std.StringHashMap(Typ),
vars: std.StringHashMap(Ref),
loop_ends: std.ArrayList(u32) = .empty,
fun_queue: std.ArrayList(Name) = .empty,
generated: HashMap(Name, void),
resolver: Resolver,
next_tmp: u32 = 0,

pub fn init(
    io: std.Io,
    gpa: std.mem.Allocator,
    typ_memo: *Memo(Typ),
    items: std.StringHashMap(*const Ast.Item),
    write_buf: []u8,
    path: []const u8,
) !Codegen {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    return .{
        .io = io,
        .gpa = gpa,
        .typ_memo = typ_memo,
        .file = file,
        .items = items,
        .resolver = .init(gpa, typ_memo),
        .writer = file.writer(io, write_buf),
        .vars = .init(gpa),
        .structs = .init(gpa),
        .consts = .init(gpa),
        .generated = .init(gpa),
    };
}

pub fn run(gen: *Codegen) !void {
    defer gen.deinit();
    try gen.genAll();
    try gen.writer.flush();
}

fn genAll(gen: *Codegen) !void {
    try gen.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    try gen.genSliceDecl();
    try gen.genFunNamed(.{ .name = "main" });
    while (gen.fun_queue.items.len != 0) {
        const name = gen.fun_queue.pop().?;
        try gen.genFunNamed(name);
    }
    try gen.print("\n", .{});
}

fn genFunNamed(gen: *Codegen, name: Name) !void {
    const item = gen.items.get(name.name).?;
    const fun = switch (item.kind) {
        .ext_fun => |ext_fun| {
            const was = try gen.generated.getOrPut(.{ .name = name.name });
            if (was.found_existing) {
                return;
            }
            try gen.genExtFun(ext_fun);
            return;
        },
        .fun => |fun| fun,
        .constant, .struc => unreachable,
    };
    const was = try gen.generated.getOrPut(name);
    if (was.found_existing) {
        return;
    }
    for (fun.header.generics, name.generics) |generic, typ| {
        try gen.resolver.map.put(generic.name, typ);
    }
    try gen.genFun(fun, name.generics);
}

const i8_typ: Typ = .i8;

fn genSliceDecl(gen: *Codegen) !void {
    try gen.print("\n%\"[]\" = type {{ ptr, i64 }}", .{});
}

fn genExtFun(gen: *Codegen, ext_fun: Ast.ExtFun) !void {
    try gen.print("\ndeclare {f} @{s}(", .{
        LlvmTyp{ .inner = ext_fun.header.ret_typ },
        ext_fun.header.name,
    });
    if (ext_fun.header.params.len != 0) {
        try gen.print("{f}", .{LlvmTyp{ .inner = ext_fun.header.params[0].typ }});
        for (ext_fun.header.params[1..]) |param| {
            try gen.print(", {f}", .{LlvmTyp{ .inner = param.typ }});
        }
    }
    try gen.print(")", .{});
}

fn genStrDecl(gen: *Codegen, str: []const u8) !Str {
    const buffer = gen.buffer.?;
    gen.buffer = null;
    defer gen.buffer = buffer;
    const unescaped = try unescape(gen.gpa, str);
    defer gen.gpa.free(unescaped.repr);
    const tmp = gen.newTmp();
    try gen.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
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

fn genFun(gen: *Codegen, fun: Ast.Fun, generics: []const Typ) !void {
    gen.buffer = gen.extra_buffer;
    const ret_resolved = try fun.header.ret_typ.resolve(&gen.resolver);
    try gen.print(
        "\ndefine {f} @\"{f}\"(",
        .{ LlvmTyp{ .inner = ret_resolved }, Name{
            .name = fun.header.name,
            .generics = generics,
        } },
    );
    var param_typ_vals = try gen.gpa.alloc(TypVal, fun.header.params.len);
    defer gen.gpa.free(param_typ_vals);
    if (fun.header.params.len != 0) {
        const first_resolved = try fun.header.params[0].typ.resolve(&gen.resolver);
        param_typ_vals[0] = try gen.genParam(first_resolved);
        for (param_typ_vals[1..], fun.header.params[1..]) |*target, param| {
            try gen.print(", ", .{});
            const resolved = try param.typ.resolve(&gen.resolver);
            target.* = try gen.genParam(resolved);
        }
    }
    try gen.print(
        \\) {{
        \\entry:
    , .{});
    gen.extra_buffer = gen.buffer.?;
    gen.buffer = .empty;
    for (
        param_typ_vals[0..fun.header.params.len],
        fun.header.params,
    ) |typ_val, param| {
        const vari = try gen.toStack(typ_val);
        try gen.vars.put(param.name, vari);
    }
    for (fun.body) |stmt| {
        try gen.genStmt(stmt);
    }
    if (fun.header.ret_typ == .prime and fun.header.ret_typ.prime == .void) {
        try gen.genRet(.{ .expr = null });
    } else {
        try gen.genUnreachable();
    }
    try gen.print("\n}}", .{});
    var buffer = gen.buffer.?;
    defer buffer.deinit(gen.gpa);
    gen.buffer = null;
    try gen.print("{s}{s}", .{ gen.extra_buffer.items, buffer.items });
    gen.extra_buffer.clearRetainingCapacity();
    gen.vars.clearRetainingCapacity();
    gen.resolver.map.clearRetainingCapacity();
}

fn genStruct(gen: *Codegen, name: Name) Error!void {
    const was = try gen.generated.getOrPut(name);
    if (was.found_existing) {
        return;
    }
    const buffer = gen.buffer.?;
    gen.buffer = .empty;
    defer {
        if (gen.buffer) |*buf| {
            buf.deinit(gen.gpa);
        }
        gen.buffer = buffer;
    }
    var fields = std.StringHashMap(Field).init(gen.gpa);
    var default_fields_vec = std.ArrayList(DefaultField).empty;
    try gen.print("\n%\"{f}\" = type {{", .{name});
    const struc = gen.items.get(name.name).?.kind.struc;
    var resolver = Resolver.init(gen.gpa, gen.typ_memo);
    defer resolver.map.deinit();
    for (struc.generics, name.generics) |generic, typ| {
        try resolver.map.put(generic.name, typ);
    }
    var struct_layout = Layout{ .size = 0, .alig = 1 };
    const field_typs = try gen.gpa.alloc(Typ, struc.fields.len);
    defer gen.gpa.free(field_typs);
    for (field_typs, struc.fields, 0..) |*typ, field, i| {
        typ.* = try field.typ.resolve(&resolver);
        const layout = try gen.getLayout(typ.*);
        appendLayout(&struct_layout, layout);
        try fields.put(field.name, .{
            .typ = typ.*,
            .index = i,
        });
        if (field.default) |expr| {
            try default_fields_vec.append(gen.gpa, .{
                .expr = expr,
                .index = i,
            });
        }
    }
    if (field_typs.len != 0) {
        try gen.print("\n  {f}", .{LlvmTyp{ .inner = field_typs[0] }});
        for (field_typs[1..]) |typ| {
            try gen.print(",\n  {f}", .{LlvmTyp{ .inner = typ }});
        }
    }
    try gen.print("\n}}", .{});
    var written = gen.buffer.?;
    gen.buffer = null;
    defer written.deinit(gen.gpa);
    try gen.print("{s}", .{written.items});
    try gen.structs.put(name, .{
        .fields = fields,
        .default_fields = try default_fields_vec.toOwnedSlice(gen.gpa),
        .layout = struct_layout,
    });
}

fn genParam(gen: *Codegen, typ: Typ) !TypVal {
    const tmp = gen.newTmp();
    try gen.print("{f} %t{}", .{ LlvmTyp{ .inner = typ }, tmp });
    return .{ .typ = typ, .val = .{ .tmp = tmp } };
}

fn genStmt(gen: *Codegen, stmt: Ast.Stmt) Error!void {
    switch (stmt.kind) {
        .for_range => |forr| try gen.genForRange(forr),
        .forr => |forr| try gen.genFor(forr),
        .op_assign => |op_assign| try gen.genOpAssign(op_assign),
        .unre => try gen.genUnreachable(),
        .ret => |ret| try gen.genRet(ret),
        .expr => |expr| _ = try gen.genExpr(expr),
        .declare => |declare| try gen.genDeclare(declare),
        .assign => |assign| try gen.genAssign(assign),
        .iff => |iff| try gen.genIf(iff),
        .whi => |whi| try gen.genWhile(whi),
        .ignore => |ignore| try gen.genIgnore(ignore),
        .brek => try gen.genBreak(),
    }
}

fn genUnreachable(gen: *Codegen) !void {
    try gen.print("\n  unreachable", .{});
}

fn genIgnore(gen: *Codegen, ignore: Ast.Stmt.Ignore) !void {
    _ = try gen.genExpr(ignore.expr);
}

fn genBreak(gen: *Codegen) !void {
    const label = gen.newTmp();
    try gen.uncond(gen.loop_ends.getLast(), label);
}

fn genWhile(gen: *Codegen, whi: Ast.Stmt.While) !void {
    const condition_label = gen.newTmp();
    try gen.uncond(condition_label, condition_label);
    try gen.genBranch(whi.branch, condition_label, true);
}

fn genForRange(gen: *Codegen, forr: Ast.Stmt.ForRange) !void {
    // int i = start
    try gen.genDeclare(.{
        .name = forr.vari,
        .expr = forr.start,
        .typ = null,
        .mutable = false,
    });
    const end = try gen.genExpr(forr.end);
    // goto cond
    // start:
    const start_label = gen.newTmp();
    const cond_label = gen.newTmp();
    try gen.uncond(cond_label, start_label);
    // i++
    const ival = try gen.genVar(forr.vari);
    const inew = try gen.genBinary(.add, ival.typ, ival.val, .{ .int = 1 });
    try gen.storeInto(gen.vars.get(forr.vari).?.val, .{ .typ = ival.typ, .val = .{ .tmp = inew } });
    // goto cond
    // cond:
    try gen.uncond(cond_label, cond_label);
    // cond = i != end
    const ival_ = try gen.loadTypVal(gen.vars.get(forr.vari).?);
    const at_end = try gen.genBinary(.neq, ival.typ, ival_.val, end.val);
    // if cond, body, end
    // body:
    const body_label = gen.newTmp();
    const end_label = gen.newTmp();
    try gen.cond(.{ .tmp = at_end }, body_label, end_label);
    // <body>
    for (forr.body) |stmt| {
        try gen.genStmt(stmt);
    }
    // goto start
    // end:
    try gen.uncond(start_label, end_label);
}

fn genFor(gen: *Codegen, forr: Ast.Stmt.For) !void {
    const slice = try gen.genExprRef(forr.expr);
    // int i = 0
    const iref = try gen.toStack(.{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = 0 },
    });
    // goto cond
    // start:
    const start_label = gen.newTmp();
    const cond_label = gen.newTmp();
    try gen.uncond(cond_label, start_label);
    // i++
    const ival = try gen.loadTypVal(iref);
    const inew = try gen.genBinary(.add, ival.typ, ival.val, .{ .int = 1 });
    try gen.storeInto(iref.val, .{ .typ = ival.typ, .val = .{ .tmp = inew } });
    // goto cond
    // cond:
    try gen.uncond(cond_label, cond_label);
    // cond = i < .len
    const ival_ = try gen.loadTypVal(iref);
    const len = try gen.genField(.{
        .expr = forr.expr,
        .name = "len",
    });
    const less = try gen.genBinary(.les, ival.typ, ival_.val, len.val);
    // if cond, body, end
    // body:
    const body_label = gen.newTmp();
    const end_label = gen.newTmp();
    try gen.cond(.{ .tmp = less }, body_label, end_label);
    // var = slice[i]
    const elem = try gen.genElemRef(slice, ival_);
    try gen.vars.put(forr.vari, elem);
    // <body>
    for (forr.body) |stmt| {
        try gen.genStmt(stmt);
    }
    // goto start
    // end:
    try gen.uncond(start_label, end_label);
}

fn cond(
    gen: *Codegen,
    condition: Val,
    then_label: u32,
    else_label: u32,
) !void {
    try gen.print(
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

fn uncond(gen: *Codegen, to: u32, next: u32) !void {
    try gen.print(
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
}

fn genIf(gen: *Codegen, iff: Ast.Stmt.If) !void {
    const end_label = gen.newTmp();
    try gen.genBranch(iff.branch, end_label, false);
    for (iff.else_ifs) |branch| {
        try gen.genBranch(branch, end_label, false);
    }
    for (iff.else_branch) |stmt| {
        try gen.genStmt(stmt);
    }
    try gen.uncond(end_label, end_label);
}

fn genBranch(gen: *Codegen, branch: Ast.Stmt.Branch, end_label: u32, loop: bool) !void {
    const condition = try gen.genExpr(branch.condition);
    const then_label = gen.newTmp();
    const else_label = gen.newTmp();
    if (loop) {
        try gen.loop_ends.append(gen.gpa, else_label);
    }
    try gen.cond(condition.val, then_label, else_label);
    for (branch.body) |stmt| {
        try gen.genStmt(stmt);
    }
    try gen.uncond(end_label, else_label);
    if (loop) {
        _ = gen.loop_ends.pop();
    }
}

fn genOpAssign(gen: *Codegen, op_assign: Ast.Stmt.OpAssign) !void {
    const vari = try gen.genExprRef(op_assign.left);
    const typ_val = try gen.genBinaryExpr(.{
        .left = op_assign.left,
        .kind = op_assign.kind,
        .right = op_assign.right,
    });
    try gen.storeInto(vari.val, typ_val);
}

fn genAssign(gen: *Codegen, assign: Ast.Stmt.Assign) !void {
    const vari = try gen.genExprRef(assign.left);
    const typ_val = try gen.genExpr(assign.expr);
    try gen.storeInto(vari.val, typ_val);
}

fn genDeclare(gen: *Codegen, declare: Ast.Stmt.Declare) !void {
    const typ_val = try gen.genExpr(declare.expr);
    const vari = try gen.toStack(typ_val);
    try gen.vars.put(declare.name, vari);
}

fn toStack(gen: *Codegen, typ_val: TypVal) !Ref {
    if (typ_val.typ == .name) {
        try gen.genStruct(typ_val.typ.name.delocate());
    }
    const tmp = gen.newTmp();
    try gen.genAlloca(tmp, typ_val.typ);
    try gen.storeInto(.{ .tmp = tmp }, typ_val);
    return .{
        .val = .{ .tmp = tmp },
        .inner_typ = typ_val.typ,
    };
}

fn genAlloca(gen: *Codegen, tmp: u32, typ: Typ) !void {
    const buffer = gen.buffer;
    // so that all allocs are in entry block
    gen.buffer = gen.extra_buffer;
    defer {
        gen.extra_buffer = gen.buffer.?;
        gen.buffer = buffer;
    }
    try gen.print("\n  %t{} = alloca {f}", .{ tmp, LlvmTyp{ .inner = typ } });
}

fn storeInto(gen: *Codegen, val: Val, typ_val: TypVal) !void {
    try gen.print("\n  store {f}, ptr {f}", .{ typ_val, val });
}

fn genCall(gen: *Codegen, call: Ast.Expr.Call) !TypVal {
    var name = Typ.Name{
        .name = call.name,
        .generics = &.{},
    };
    var params: []const Ast.Param = &.{};
    if (gen.items.get(call.name)) |item| {
        if (item.kind == .fun) {
            name.generics = call.generics;
        }
        try gen.fun_queue.append(gen.gpa, .{
            .name = call.name,
            .generics = call.generics,
        });
        params = item.getHeader().?.params;
    }
    const mtmp = if (gen.vars.get(name.name)) |vari| try gen.load(vari) else null;
    var arg_typ_vals = try gen.gpa.alloc(TypVal, call.args.len);
    defer gen.gpa.free(arg_typ_vals);
    for (arg_typ_vals, call.args, 0..) |*target, arg, i| {
        target.* = try gen.genExpr(arg);
        if (params.len != 0) {
            if (params[i].typ == .slice and target.typ == .ptr) {
                target.* = try gen.genArrayToSlice(target.typ.ptr.typ.array, target.val);
            }
        }
    }
    const ret_tmp = gen.newTmp();
    if (call.ret_typ != .prime or call.ret_typ.prime != .void) {
        try gen.print("\n  %t{} = ", .{ret_tmp});
    } else {
        try gen.print("\n  ", .{});
    }
    try gen.print("call {f} ", .{LlvmTyp{ .inner = call.ret_typ }});
    if (mtmp) |tmp| {
        try gen.print("%t{}", .{tmp});
    } else {
        try gen.print("@\"{f}\"", .{name.delocate()});
    }
    try gen.print("(", .{});
    if (call.args.len != 0) {
        try gen.print("{f}", .{arg_typ_vals[0]});
        for (arg_typ_vals[1..]) |val| {
            try gen.print(", {f}", .{val});
        }
    }
    try gen.print(")", .{});
    return .{ .val = .{ .tmp = ret_tmp }, .typ = call.ret_typ };
}

fn genArrayToSlice(gen: *Codegen, array: Ast.Typ.Array, val: Val) !TypVal {
    var res = TypVal{
        .typ = .{ .slice = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .val = .undef,
    };
    try gen.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = array.typ,
            .mutable = false,
        } },
        .val = val,
    }, 0);
    try gen.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = array.len },
    }, 1);
    return res;
}

fn newTmp(gen: *Codegen) u32 {
    gen.next_tmp += 1;
    return gen.next_tmp - 1;
}

fn genRet(gen: *Codegen, ret: Ast.Stmt.Return) !void {
    if (ret.expr) |expr| {
        const val = try gen.genExpr(expr);
        try gen.print("\n  ret {f}", .{val});
    } else {
        try gen.print("\n  ret void", .{});
    }
}

fn genExpr(gen: *Codegen, expr: Ast.Expr) Error!TypVal {
    switch (expr.kind) {
        .subslice => |subslice| return gen.genSubslice(subslice.*),
        .sizeof => |typ| return gen.genSizeof(typ),
        .array => |array| return gen.genArray(array),
        .unary => |unary| return gen.genUnary(unary.*),
        .struc => |struc| return gen.genStructExpr(struc),
        .int => |int| return genInt(int),
        .str => |str| return gen.genStr(str),
        .vari => |name| return gen.genVar(name),
        .fn_ptr => |name| return gen.genFnPtr(name),
        .char => |char| return genChar(char),
        .bool => |boo| return genBool(boo),
        .undef => |undef| return genUndef(undef),
        .call => |call| return gen.genCall(call),
        .binary => |binary| return gen.genBinaryExpr(binary.*),
        .field => |field| return gen.genField(field.*),
        .named_struc => |struc| return gen.genNamedStructExpr(struc),
        .elem => |elem| return gen.genElem(elem.*),
    }
}

fn genSizeof(gen: *Codegen, typ: Typ) !TypVal {
    const resolved = try typ.resolve(&gen.resolver);
    const layout = try gen.getLayout(resolved);
    return .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = layout.size },
    };
}

fn getLayout(gen: *Codegen, typ: Typ) !Layout {
    switch (typ) {
        .prime => |prime| return primeLayout(prime),
        .array => |array| {
            const inner = try gen.getLayout(array.typ.*);
            return .{
                .size = inner.size * array.len,
                .alig = inner.alig,
            };
        },
        .fun, .ptr => return .make(8, 8),
        .slice => return .make(16, 8),
        .name => |name| {
            try gen.genStruct(name.delocate());
            return gen.structs.get(name.delocate()).?.layout;
        },
    }
}

fn genArray(gen: *Codegen, array: Ast.Expr.Array) !TypVal {
    var res = TypVal{
        .typ = array.typ,
        .val = .undef,
    };
    for (array.exprs, 0..) |expr, i| {
        const typ_val = try gen.genExpr(expr);
        try gen.genIV(&res, typ_val, i);
    }
    return res;
}

fn genUnary(gen: *Codegen, unary: Ast.Expr.Unary) !TypVal {
    switch (unary.kind) {
        .deref => return gen.genDeref(unary.expr),
        .notb => return gen.genNotb(unary.expr),
        .ptr => return gen.genPtr(unary.expr),
        .neg => return gen.genNeg(unary.expr),
    }
}

fn genNeg(gen: *Codegen, expr: Ast.Expr) !TypVal {
    const typ_val = try gen.genExpr(expr);
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %t{d} = sub {f} 0, {f}",
        .{ tmp, LlvmTyp{ .inner = typ_val.typ }, typ_val.val },
    );
    return .{
        .typ = typ_val.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genDerefRef(gen: *Codegen, expr: Ast.Expr) !Ref {
    const typ_val = try gen.genExpr(expr);
    return .{
        .inner_typ = typ_val.typ.ptr.typ.*,
        .val = typ_val.val,
    };
}

fn genDeref(gen: *Codegen, deref: Ast.Expr) !TypVal {
    const ref = try gen.genDerefRef(deref);
    return gen.loadTypVal(ref);
}

fn loadTypVal(gen: *Codegen, ref: Ref) !TypVal {
    const tmp = try gen.load(ref);
    return .{
        .typ = ref.inner_typ,
        .val = .{ .tmp = tmp },
    };
}

fn genNotb(gen: *Codegen, expr: Ast.Expr) !TypVal {
    const typ_val = try gen.genExpr(expr);
    const tmp = gen.newTmp();
    try gen.print("\n  %t{d} = xor {f}, -1", .{ tmp, typ_val });
    return .{
        .typ = typ_val.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genPtr(gen: *Codegen, expr: Ast.Expr) !TypVal {
    const ref = try gen.genExprRef(expr);
    return gen.makePtrFromRef(ref);
}

fn makePtrFromRef(gen: *Codegen, ref: Ref) !TypVal {
    return .{
        .typ = .{ .ptr = .{
            .typ = try gen.typ_memo.box(ref.inner_typ),
            .mutable = false,
        } },
        .val = ref.val,
    };
}

fn genUndef(undef: Ast.Expr.Undef) !TypVal {
    return .{ .typ = undef.typ, .val = .undef };
}

fn genFieldRef(gen: *Codegen, field: Ast.Expr.Field) !Ref {
    var vari = try gen.genExprRef(field.expr);
    if (vari.inner_typ == .ptr) {
        const tmp = try gen.load(vari);
        vari = .{
            .inner_typ = vari.inner_typ.ptr.typ.*,
            .val = .{ .tmp = tmp },
        };
    }
    if (vari.inner_typ == .array) {
        std.debug.assert(std.mem.eql(u8, field.name, "len"));
        return gen.toStack(.{
            .typ = .{ .prime = .u64 },
            .val = .{ .int = vari.inner_typ.array.len },
        });
    }
    const info = gen.getFieldInfo(vari.inner_typ, field.name);
    const tmp = try gen.genGEPIB(vari, .int(info.index));
    return .{
        .inner_typ = info.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genField(gen: *Codegen, field: Ast.Expr.Field) !TypVal {
    const ref = try gen.genFieldRef(field);
    return gen.loadTypVal(ref);
}

fn genElemExprRef(gen: *Codegen, elem: Ast.Expr.Elem) !Ref {
    const ref = try gen.genExprRef(elem.expr);
    const index = try gen.genExpr(elem.index);
    return gen.genElemRef(ref, index);
}

fn genElemRef(gen: *Codegen, from: Ref, index: TypVal) !Ref {
    switch (from.inner_typ) {
        .array => {
            const tmp = try gen.genGEPIB(from, index);
            return .{
                .inner_typ = from.inner_typ.array.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        .slice => |slice| {
            const ptrptr = try gen.genGEPIB(from, .int(0));
            const ptr = try gen.load(.{
                .inner_typ = .{ .ptr = .{
                    .typ = slice.typ,
                    .mutable = false,
                } },
                .val = .{ .tmp = ptrptr },
            });
            const tmp = try gen.genGEP(slice.typ.*, ptr, index);
            return .{
                .inner_typ = slice.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        else => unreachable,
    }
}

fn genGEP(gen: *Codegen, typ: Typ, ptr: u32, index: TypVal) !u32 {
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %t{} = getelementptr {f}, ptr %t{}, {f}",
        .{ tmp, LlvmTyp{ .inner = typ }, ptr, index },
    );
    return tmp;
}

fn genGEPIB(gen: *Codegen, ref: Ref, index: TypVal) !u32 {
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %t{} = getelementptr inbounds {f}, ptr {f}, i32 0, {f}",
        .{ tmp, LlvmTyp{ .inner = ref.inner_typ }, ref.val, index },
    );
    return tmp;
}

fn genElem(gen: *Codegen, elem: Ast.Expr.Elem) !TypVal {
    const ref = try gen.genElemExprRef(elem);
    return gen.loadTypVal(ref);
}

fn genSubslice(gen: *Codegen, subslice: Ast.Expr.Subslice) !TypVal {
    const ref = try gen.genExprRef(subslice.expr);
    const start = try gen.genExpr(subslice.start);
    const end = try gen.genExpr(subslice.end);
    const ptr_ref = try gen.genElemRef(ref, start);
    const ptr = try gen.makePtrFromRef(ptr_ref);
    const len = try gen.genBinary(.sub, start.typ, end.val, start.val);
    var res = TypVal{ .typ = .{ .slice = .{
        .typ = try gen.typ_memo.box(ptr_ref.inner_typ),
        .mutable = false,
    } }, .val = .undef };
    try gen.genIV(&res, ptr, 0);
    try gen.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .tmp = len },
    }, 1);
    return res;
}

fn genExprRef(gen: *Codegen, expr: Ast.Expr) Error!Ref {
    switch (expr.kind) {
        .unary => |unary| return gen.genUnaryRef(unary.*),
        .vari => |name| return gen.genVarRef(name),
        .field => |field| return gen.genFieldRef(field.*),
        .elem => |elem| return gen.genElemExprRef(elem.*),
        .subslice,
        .sizeof,
        .fn_ptr,
        .call,
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
            const typ_val = try gen.genExpr(expr);
            return gen.toStack(typ_val);
        },
    }
}

fn genUnaryRef(gen: *Codegen, unary: Ast.Expr.Unary) !Ref {
    switch (unary.kind) {
        .deref => return gen.genDerefRef(unary.expr),
        .notb, .ptr, .neg => {
            const typ_val = try gen.genUnary(unary);
            const vari = try gen.toStack(typ_val);
            return vari;
        },
    }
}

fn load(gen: *Codegen, vari: Ref) !u32 {
    const to = gen.newTmp();
    try gen.print(
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

fn genStr(gen: *Codegen, str: []const u8) !TypVal {
    const info = try gen.genStrDecl(str);
    const ptr_u8 = try gen.typ_memo.box(.{ .prime = .u8 });
    var res = TypVal{
        .typ = .{ .slice = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .val = .undef,
    };
    try gen.genIV(&res, .{
        .typ = .{ .ptr = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .val = .{ .str = info.tmp },
    }, 0);
    try gen.genIV(&res, .{
        .typ = .{ .prime = .u64 },
        .val = .{ .int = info.len },
    }, 1);
    return res;
}

fn genStructExpr(gen: *Codegen, struc: Ast.Expr.Struct) !TypVal {
    if (struc.typ == .name) {
        try gen.genStruct(struc.typ.name.delocate());
    }
    var res = TypVal{
        .typ = struc.typ,
        .val = .undef,
    };
    if (struc.typ == .name) {
        for (gen.structs.get(struc.typ.name.delocate()).?.default_fields) |field| {
            const typ_val = try gen.genExpr(field.expr);
            try gen.genIV(&res, typ_val, field.index);
        }
    }
    for (struc.fields) |field| {
        const typ_val = try gen.genExpr(field.expr);
        const info = gen.getFieldInfo(struc.typ, field.name);
        try gen.genIV(&res, typ_val, info.index);
    }
    return res;
}

fn genIV(gen: *Codegen, to: *TypVal, typ_val: TypVal, index: u64) !void {
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %t{} = insertvalue {f}, {f}, {d}",
        .{ tmp, to, typ_val, index },
    );
    to.val = .{ .tmp = tmp };
}

fn genNamedStructExpr(gen: *Codegen, named: Ast.Expr.Struct.Named) !TypVal {
    return gen.genStructExpr(named.struc);
}

fn genBinaryExpr(gen: *Codegen, binary: Ast.Expr.Binary) !TypVal {
    const left = try gen.genExpr(binary.left);
    const right = try gen.genExpr(binary.right);
    const tmp = try gen.genBinary(binary.kind, left.typ, left.val, right.val);
    return .{
        .typ = binOpRetTyp(binary.kind, left.typ),
        .val = .{ .tmp = tmp },
    };
}

fn genBinary(gen: *Codegen, kind: Ast.Expr.Binary.Kind, typ: Typ, a: Val, b: Val) !u32 {
    const tmp = gen.newTmp();
    try gen.print("\n  %t{} = ", .{tmp});
    try gen.genBinOp(kind);
    try gen.print(" {f} {f}, {f}", .{ LlvmTyp{ .inner = typ }, a, b });
    return tmp;
}

fn binOpRetTyp(kind: Ast.Expr.Binary.Kind, child_typ: Typ) Typ {
    return switch (kind.getClass()) {
        .arith => child_typ,
        .bool => .{ .prime = .bool },
    };
}

fn genBinOp(gen: *Codegen, kind: Ast.Expr.Binary.Kind) !void {
    switch (kind) {
        .moreq => try gen.print("icmp sge", .{}),
        .orb => try gen.print("or", .{}),
        .andb => try gen.print("and", .{}),
        .add => try gen.print("add", .{}),
        .sub => try gen.print("sub", .{}),
        .mul => try gen.print("mul", .{}),
        .div => try gen.print("sdiv", .{}),
        .rem => try gen.print("srem", .{}),
        .equ => try gen.print("icmp eq", .{}),
        .les => try gen.print("icmp slt", .{}),
        .neq => try gen.print("icmp ne", .{}),
    }
}

fn genVarRef(gen: *Codegen, name: []const u8) !Ref {
    return gen.vars.get(name) orelse {
        try gen.genConst(name);
        return .{
            .inner_typ = gen.consts.get(name).?,
            .val = .{ .global = name },
        };
    };
}

fn genConst(gen: *Codegen, name: []const u8) !void {
    const was = try gen.generated.getOrPut(.{ .name = name });
    if (was.found_existing) {
        return;
    }
    const expr = gen.items.get(name).?.kind.constant.expr;
    const buffer = gen.buffer.?;
    gen.buffer = .empty;
    defer {
        if (gen.buffer) |*buf| {
            buf.deinit(gen.gpa);
        }
        gen.buffer = buffer;
    }

    try gen.print("\n@{s} = private unnamed_addr constant ", .{name});
    const typ = try gen.genConstExpr(expr);
    try gen.consts.put(name, typ);
    var written = gen.buffer.?;
    gen.buffer = null;
    defer written.deinit(gen.gpa);
    try gen.print("{s}", .{written.items});
}

fn genConstExpr(gen: *Codegen, expr: Ast.Expr) Error!Typ {
    switch (expr.kind) {
        .str => |str| return gen.genConstStr(str),
        .named_struc => |named| return gen.genConstStruc(named.struc),
        .struc => |struc| return gen.genConstStruc(struc),
        .array => |array| return gen.genConstArray(array),
        else => unreachable,
    }
}

fn genConstArray(gen: *Codegen, array: Ast.Expr.Array) !Typ {
    try gen.print("{f} [", .{LlvmTyp{ .inner = array.typ }});
    if (array.exprs.len != 0) {
        try gen.print("\n  ", .{});
        _ = try gen.genConstExpr(array.exprs[0]);
        for (array.exprs[1..]) |expr| {
            try gen.print(",\n  ", .{});
            _ = try gen.genConstExpr(expr);
        }
    }
    try gen.print("\n]", .{});
    return array.typ;
}

fn genConstStruc(gen: *Codegen, struc: Ast.Expr.Struct) !Typ {
    if (struc.typ == .name) {
        try gen.genStruct(struc.typ.name.delocate());
    }
    try gen.print("{f} {{", .{LlvmTyp{ .inner = struc.typ }});
    if (struc.fields.len != 0) {
        const fields = try gen.gpa.alloc(Ast.Expr, struc.fields.len);
        defer gen.gpa.free(fields);
        if (struc.typ == .name) {
            for (gen.structs.get(struc.typ.name.delocate()).?.default_fields) |field| {
                fields[field.index] = field.expr;
            }
        }
        for (struc.fields) |field| {
            const info = gen.getFieldInfo(struc.typ, field.name);
            fields[info.index] = field.expr;
        }
        try gen.print("\n  ", .{});
        _ = try gen.genConstExpr(fields[0]);
        for (fields[1..]) |expr| {
            try gen.print(",\n  ", .{});
            _ = try gen.genConstExpr(expr);
        }
    }
    try gen.print("\n}}", .{});
    return struc.typ;
}

fn getFieldInfo(gen: *Codegen, typ: Typ, name: []const u8) Field {
    return if (typ == .name)
        gen.structs.get(typ.name.delocate()).?.fields.get(name).?
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

fn genConstStr(gen: *Codegen, str: []const u8) !Typ {
    const info = try gen.genStrDecl(str);
    try gen.print("%\"[]\" {{ ptr @.s{d}, i64 {d} }}", .{ info.tmp, info.len });
    return .{ .slice = .{
        .typ = try gen.typ_memo.box(.{ .prime = .u8 }),
        .mutable = false,
    } };
}

fn genVar(gen: *Codegen, name: []const u8) !TypVal {
    const ref = try gen.genVarRef(name);
    return gen.loadTypVal(ref);
}

fn genFnPtr(gen: *Codegen, name: []const u8) !TypVal {
    const item = gen.items.get(name).?;
    try gen.fun_queue.append(gen.gpa, .{ .name = name, .generics = &.{} });
    const header = item.getHeader().?;
    const params = try gen.typ_memo.arena.allocator().alloc(Typ, header.params.len);
    for (params, header.params) |*target, param| {
        target.* = param.typ;
    }
    return .{
        .typ = .{ .fun = .{
            .params = params,
            .ret_typ = try gen.typ_memo.box(header.ret_typ),
        } },
        .val = .{ .global = name },
    };
}

fn print(gen: *Codegen, comptime fmt: []const u8, args: anytype) !void {
    if (gen.buffer) |*buffer| {
        try buffer.print(gen.gpa, fmt, args);
    } else {
        try gen.writer.interface.print(fmt, args);
    }
}

const Error = error{ WriteFailed, OutOfMemory };

fn deinit(gen: *Codegen) void {
    gen.vars.deinit();
    gen.file.close(gen.io);
    gen.loop_ends.deinit(gen.gpa);
    gen.fun_queue.deinit(gen.gpa);
    gen.generated.deinit();
    gen.resolver.map.deinit();
    gen.items.deinit();
    gen.consts.deinit();
    gen.deinitStructs();
    gen.extra_buffer.deinit(gen.gpa);
    gen.* = undefined;
}

fn deinitStructs(gen: *Codegen) void {
    var iter = gen.structs.valueIterator();
    while (iter.next()) |info| {
        info.fields.deinit();
        gen.gpa.free(info.default_fields);
    }
    gen.structs.deinit();
}

fn appendLayout(res: *Layout, layout: Layout) void {
    res.alig = @max(res.alig, layout.alig);
    // padding
    if (layout.size % layout.alig != 0) {
        res.size += layout.alig - (res.size % layout.alig);
    }
    res.size += layout.size;
}

fn primeLayout(prime: Ast.Typ.Prime) !Layout {
    return switch (prime) {
        .u8, .bool => .make(1, 1),
        .i32, .u32 => .make(4, 4),
        .u64 => .make(8, 8),
        .void => .make(0, 1),
    };
}
