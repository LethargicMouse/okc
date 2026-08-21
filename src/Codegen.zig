const std = @import("std");

const Ast = @import("Ast.zig");
const builtin = @import("builtin.zig");
const Info = @import("Info.zig");
const LlvmTyps = @import("LlvmTyps.zig");
const Typ = LlvmTyps.Typ;

const Unescaped = struct { len: usize, repr: []const u8 };

const TypVal = struct {
    typ: Typ,
    val: Val,

    pub fn format(
        typ_val: TypVal,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{f} {f}", .{ typ_val.typ, typ_val.val });
    }
};

const Val = union(enum) {
    int: u64,
    str: usize,
    tmp: u32,
    undef,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("{d}", .{int}),
            .str => |str| try writer.print("@.s{}", .{str}),
            .tmp => |tmp| try writer.print("%{}", .{tmp}),
            .undef => try writer.writeAll("poison"),
        }
    }
};

const Var = struct {
    tmp: u32,
    inner_typ: Typ,
};

const Field = struct {
    index: usize,
    typ: Typ,
};

const Struct = struct {
    fields: std.StringHashMap(Field),
};

const Codegen = @This();

io: std.Io,
gpa: std.mem.Allocator,
info: Info,
file: std.Io.File,
writer: std.Io.File.Writer,
llvm_typs: LlvmTyps,
fun_ret_typs: std.StringHashMap(Typ),
vars: std.StringHashMap(Var),
structs: std.StringHashMap(Struct),
str_lens: std.ArrayList(usize) = .empty,
loop_ends: std.ArrayList(u32),
next_tmp: u32 = 0,

pub fn init(
    io: std.Io,
    gpa: std.mem.Allocator,
    llvm_typs: LlvmTyps,
    write_buf: []u8,
    path: []const u8,
    info: Info,
) !Codegen {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    return .{
        .io = io,
        .gpa = gpa,
        .llvm_typs = llvm_typs,
        .info = info,
        .file = file,
        .writer = file.writer(io, write_buf),
        .fun_ret_typs = std.StringHashMap(Typ).init(gpa),
        .vars = std.StringHashMap(Var).init(gpa),
        .structs = std.StringHashMap(Struct).init(gpa),
        .loop_ends = std.ArrayList(u32).empty,
    };
}

pub fn run(gen: *Codegen, ast: Ast) !void {
    defer gen.deinit();
    try gen.genAst(ast);
    try gen.writer.flush();
}

fn genAst(gen: *Codegen, ast: Ast) !void {
    try gen.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    try gen.genStrStruct();
    for (ast.strs, 0..) |str, i| {
        const len = try gen.genStrDecl(i, str);
        try gen.str_lens.append(gen.gpa, len);
    }
    for (ast.items) |item| {
        try gen.regItem(item);
    }
    for (ast.items) |item| {
        try gen.genItem(item);
    }
    try gen.print("\n", .{});
}

fn regItem(gen: *Codegen, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => |ext_fun| try gen.regHeader(ext_fun.header),
        .fun => |fun| try gen.regHeader(fun.header),
        .struc => |struc| try gen.regAndGenStruct(struc),
    }
}

fn genItem(gen: *Codegen, item: Ast.Item) !void {
    switch (item) {
        .ext_fun => |ext_fun| try gen.genExtFun(ext_fun),
        .fun => |fun| try gen.genFun(fun),
        .struc => {}, // already gen'd during reg phase
    }
}

const i8_typ: Typ = .i8;

fn regAndGenStruct(gen: *Codegen, struc: Ast.Struct) !void {
    var res = Struct{
        .fields = std.StringHashMap(Field).init(gen.gpa),
    };
    try gen.print("\n%{s} = type {{", .{struc.name});
    for (struc.fields, 0..) |field, i| {
        const typ = try gen.llvm_typs.makeTyp(field.typ);
        try res.fields.put(field.name, .{
            .typ = typ,
            .index = i,
        });
        if (i != 0) {
            try gen.print(",", .{});
        }
        try gen.print("\n  {f}", .{typ});
    }
    try gen.print("\n}}", .{});
    try gen.structs.put(struc.name, res);
}

fn genStrStruct(gen: *Codegen) !void {
    try gen.regAndGenStruct(builtin.str_struct);
}

fn regHeader(gen: *Codegen, header: Ast.Header) !void {
    const typ = try gen.llvm_typs.makeTyp(header.ret_typ);
    try gen.fun_ret_typs.put(header.name, typ);
}

fn genExtFun(gen: *Codegen, ext_fun: Ast.ExtFun) !void {
    try gen.print("\ndeclare i32 @{s}(", .{ext_fun.header.name});
    if (ext_fun.header.params.len != 0) {
        const first_typ = try gen.llvm_typs.makeTyp(ext_fun.header.params[0].typ);
        try gen.print("{f}", .{first_typ});
        for (ext_fun.header.params[1..]) |param| {
            const typ = try gen.llvm_typs.makeTyp(param.typ);
            try gen.print(", {f}", .{typ});
        }
    }
    try gen.print(")", .{});
}

fn genStrDecl(gen: *Codegen, index: usize, str: []const u8) !usize {
    const unescaped = try unescape(gen.gpa, str);
    defer gen.gpa.free(unescaped.repr);
    try gen.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
        index,
        unescaped.len + 1,
        unescaped.repr,
    });
    return unescaped.len;
}

fn unescape(gpa: std.mem.Allocator, str: []const u8) !Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, str.len);
    var i: usize = 0;
    var len = str.len;
    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '\\' => {
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
            },
            else => try vec.append(gpa, str[i]),
        }
    }
    const repr = try vec.toOwnedSlice(gpa);
    return .{
        .len = len,
        .repr = repr,
    };
}

fn genFun(gen: *Codegen, fun: Ast.Fun) !void {
    const ret_typ = try gen.llvm_typs.makeTyp(fun.header.ret_typ);
    try gen.print("\ndefine {f} @{s}(", .{ ret_typ, fun.header.name });
    var param_typ_vals: [10]TypVal = undefined;
    if (fun.header.params.len != 0) {
        param_typ_vals[0] = try gen.genParam(fun.header.params[0]);
        for (fun.header.params[1..], 1..) |param, i| {
            try gen.print(", ", .{});
            param_typ_vals[i] = try gen.genParam(param);
        }
    }
    try gen.print(
        \\) {{
        \\entry:
    , .{});
    for (
        param_typ_vals[0..fun.header.params.len],
        fun.header.params,
    ) |typ_val, param| {
        const vari = try gen.toStack(typ_val);
        try gen.vars.put(param.name, vari);
    }
    for (fun.body) |statement| {
        try gen.genStatement(statement);
    }
    if (ret_typ == .void) {
        try gen.genRet(.{ .expr = null });
    } else {
        try gen.genUnreachable();
    }
    try gen.print("\n}}", .{});
}

fn genParam(gen: *Codegen, param: Ast.Param) !TypVal {
    const typ = try gen.llvm_typs.makeTyp(param.typ);
    const tmp = gen.newTmp();
    try gen.print("{f} %{}", .{ typ, tmp });
    return .{ .typ = typ, .val = .{ .tmp = tmp } };
}

fn genStatement(gen: *Codegen, statement: Ast.Statement) Error!void {
    switch (statement.kind) {
        .op_assign => |op_assign| try gen.genOpAssign(op_assign),
        .unre => try gen.genUnreachable(),
        .ret => |ret| try gen.genRet(ret),
        .expr => |expr| _ = try gen.genExpr(expr),
        .declare => |declare| try gen.genDeclare(declare),
        .assign => |assign| try gen.genAssign(assign),
        .iff => |iff| try gen.genIf(iff),
        .whi => |whi| try gen.genWhile(whi),
        .ignore => |ignore| try gen.genIgnore(ignore),
        .mut_declare => |declare| try gen.genDeclare(declare),
        .brek => try gen.genBreak(),
    }
}

fn genUnreachable(gen: *Codegen) !void {
    try gen.print("\n  unreachable", .{});
}

fn genIgnore(gen: *Codegen, ignore: Ast.Ignore) !void {
    _ = try gen.genExpr(ignore.expr);
}

fn genBreak(gen: *Codegen) !void {
    const label = gen.newTmp();
    try gen.uncond(gen.loop_ends.getLast(), label);
}

fn genWhile(gen: *Codegen, whi: Ast.While) !void {
    const condition_label = gen.newTmp();
    try gen.uncond(condition_label, condition_label);
    try gen.genBranch(whi.branch, condition_label, true);
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

fn genIf(gen: *Codegen, iff: Ast.If) !void {
    const end_label = gen.newTmp();
    try gen.genBranch(iff.branch, end_label, false);
    for (iff.else_ifs) |branch| {
        try gen.genBranch(branch, end_label, false);
    }
    for (iff.else_branch) |statement| {
        try gen.genStatement(statement);
    }
    try gen.uncond(end_label, end_label);
}

fn genBranch(gen: *Codegen, branch: Ast.Branch, end_label: u32, loop: bool) !void {
    const condition = try gen.genExpr(branch.condition);
    const then_label = gen.newTmp();
    const else_label = gen.newTmp();
    if (loop) {
        try gen.loop_ends.append(gen.gpa, else_label);
    }
    try gen.cond(condition.val, then_label, else_label);
    for (branch.body) |statement| {
        try gen.genStatement(statement);
    }
    try gen.uncond(end_label, else_label);
    if (loop) {
        _ = gen.loop_ends.pop();
    }
}

fn genOpAssign(gen: *Codegen, op_assign: Ast.OpAssign) !void {
    const vari = try gen.genExprRef(op_assign.left);
    const typ_val = try gen.genBinary(.{
        .left = op_assign.left,
        .kind = op_assign.kind,
        .right = op_assign.right,
    });
    try gen.storeInto(vari.tmp, typ_val);
}

fn genAssign(gen: *Codegen, assign: Ast.Assign) !void {
    const vari = try gen.genExprRef(assign.left);
    const typ_val = try gen.genExpr(assign.expr);
    try gen.storeInto(vari.tmp, typ_val);
}

fn genDeclare(gen: *Codegen, declare: Ast.Declare) !void {
    const typ_val = try gen.genExpr(declare.expr);
    const vari = try gen.toStack(typ_val);
    try gen.vars.put(declare.name, vari);
}

fn toStack(gen: *Codegen, typ_val: TypVal) !Var {
    const tmp = gen.newTmp();
    try gen.print("\n  %{} = alloca {f}", .{ tmp, typ_val.typ });
    try gen.storeInto(tmp, typ_val);
    return .{ .tmp = tmp, .inner_typ = typ_val.typ };
}

fn storeInto(gen: *Codegen, tmp: u32, typ_val: TypVal) !void {
    try gen.print("\n  store {f}, ptr %{}", .{ typ_val, tmp });
}

fn genCall(gen: *Codegen, call: Ast.Call) !TypVal {
    var arg_typ_vals = try std.ArrayList(TypVal).initCapacity(gen.gpa, call.args.len);
    defer arg_typ_vals.deinit(gen.gpa);
    for (call.args) |arg| {
        const typ_val = try gen.genExpr(arg);
        try arg_typ_vals.append(gen.gpa, typ_val);
    }
    const ret_typ = gen.fun_ret_typs.get(call.name).?;
    const ret_tmp = gen.newTmp();
    if (ret_typ != .void) {
        try gen.print("\n  %{} = ", .{ret_tmp});
    } else {
        try gen.print("\n  ", .{});
    }
    try gen.print("call {f} @{s}(", .{ ret_typ, call.name });
    if (call.args.len != 0) {
        try gen.print("{f}", .{arg_typ_vals.items[0]});
        for (arg_typ_vals.items[1..]) |val| {
            try gen.print(", {f}", .{val});
        }
    }
    try gen.print(")", .{});
    return .{ .val = .{ .tmp = ret_tmp }, .typ = ret_typ };
}

fn newTmp(gen: *Codegen) u32 {
    gen.next_tmp += 1;
    return gen.next_tmp - 1;
}

fn genRet(gen: *Codegen, ret: Ast.Return) !void {
    if (ret.expr) |expr| {
        const val = try gen.genExpr(expr);
        try gen.print("\n  ret {f}", .{val});
    } else {
        try gen.print("\n  ret void", .{});
    }
}

fn genExpr(gen: *Codegen, expr: Ast.Expr) Error!TypVal {
    switch (expr.kind) {
        .unary => |unary| return gen.genUnary(unary.*),
        .infer_struc => |struc| return gen.genInferStruc(struc),
        .int => |int| return genInt(int),
        .str => |str| return gen.genStr(str),
        .vari => |name| return gen.genVar(name),
        .char => |char| return genChar(char),
        .bool => |boo| return genBool(boo),
        .undef => |undef| return gen.genUndef(undef),
        .call => |call| return gen.genCall(call),
        .binary => |binary| return gen.genBinary(binary.*),
        .field => |field| return gen.genField(field.*),
        .struc => |struc| return gen.genStructExpr(struc),
        .elem => |elem| return gen.genElem(elem.*),
    }
}

fn genUnary(gen: *Codegen, unary: Ast.Unary) !TypVal {
    switch (unary.kind) {
        .deref => return gen.genDeref(unary.expr),
        .notb => return gen.genNotb(unary.expr),
        .ptr => return gen.genPtr(unary.expr),
        .mut_ptr => return gen.genPtr(unary.expr),
    }
}

fn genDerefRef(gen: *Codegen, expr: Ast.Expr) !Var {
    const typ_val = try gen.genExpr(expr);
    const typ = typ_val.typ.ptr.*;
    return .{
        .inner_typ = typ,
        .tmp = typ_val.val.tmp,
    };
}

fn genDeref(gen: *Codegen, deref: Ast.Expr) !TypVal {
    const ref = try gen.genDerefRef(deref);
    return gen.loadTypVal(ref);
}

fn loadTypVal(gen: *Codegen, vari: Var) !TypVal {
    const tmp = try gen.load(vari);
    return .{
        .typ = vari.inner_typ,
        .val = .{ .tmp = tmp },
    };
}

fn genNotb(gen: *Codegen, expr: Ast.Expr) !TypVal {
    const typ_val = try gen.genExpr(expr);
    const tmp = gen.newTmp();
    try gen.print("\n  %{d} = xor {f}, -1", .{ tmp, typ_val });
    return .{
        .typ = typ_val.typ,
        .val = .{ .tmp = tmp },
    };
}

fn genPtr(gen: *Codegen, expr: Ast.Expr) !TypVal {
    const vari = try gen.genExprRef(expr);
    const typ = try gen.llvm_typs.box(vari.inner_typ);
    return .{
        .typ = .{ .ptr = typ },
        .val = .{ .tmp = vari.tmp },
    };
}

fn genUndef(gen: *Codegen, undef: Ast.Undef) !TypVal {
    const typ = gen.info.typs[undef.typ_id];
    return .{ .typ = typ, .val = .undef };
}

fn genFieldRef(gen: *Codegen, field: Ast.Field) !Var {
    const vari = try gen.genExprRef(field.expr);
    const struc = gen.structs.get(vari.inner_typ.name).?;
    const fiel = struc.fields.get(field.name).?;
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %{} = getelementptr inbounds %{s}, ptr %{}, i32 0, i32 {}",
        .{ tmp, vari.inner_typ.name, vari.tmp, fiel.index },
    );
    return .{ .inner_typ = fiel.typ, .tmp = tmp };
}

fn genField(gen: *Codegen, field: Ast.Field) !TypVal {
    const ref = try gen.genFieldRef(field);
    return gen.loadTypVal(ref);
}

fn genElemRef(gen: *Codegen, elem: Ast.Elem) !Var {
    const ref = try gen.genExprRef(elem.expr);
    const index = try gen.genExpr(elem.index);
    const tmp = gen.newTmp();
    try gen.print(
        "\n  %{} = getelementptr inbounds {f}, ptr %{d}, i32 0, {f}",
        .{ tmp, ref.inner_typ, ref.tmp, index },
    );
    return .{
        .inner_typ = ref.inner_typ.array.typ.*,
        .tmp = tmp,
    };
}

fn genElem(gen: *Codegen, elem: Ast.Elem) !TypVal {
    const ref = try gen.genElemRef(elem);
    return gen.loadTypVal(ref);
}

fn genExprRef(gen: *Codegen, expr: Ast.Expr) Error!Var {
    switch (expr.kind) {
        .unary => |unary| return gen.genUnaryRef(unary.*),
        .vari => |name| return gen.vars.get(name).?,
        .field => |field| return gen.genFieldRef(field.*),
        .elem => |elem| return gen.genElemRef(elem.*),
        .call,
        .binary,
        .struc,
        .int,
        .str,
        .char,
        .undef,
        .bool,
        .infer_struc,
        => {
            const typ_val = try gen.genExpr(expr);
            const vari = try gen.toStack(typ_val);
            return vari;
        },
    }
}

fn genUnaryRef(gen: *Codegen, unary: Ast.Unary) !Var {
    switch (unary.kind) {
        .deref => return gen.genDerefRef(unary.expr),
        .mut_ptr, .notb, .ptr => {
            const typ_val = try gen.genUnary(unary);
            const vari = try gen.toStack(typ_val);
            return vari;
        },
    }
}

fn load(gen: *Codegen, vari: Var) !u32 {
    const to = gen.newTmp();
    try gen.print(
        "\n  %{} = load {f}, ptr %{}",
        .{ to, vari.inner_typ, vari.tmp },
    );
    return to;
}

fn genInt(int_str: []const u8) TypVal {
    const int = std.fmt.parseInt(u64, int_str, 10) catch unreachable;
    return .{
        .typ = .i32,
        .val = .{ .int = int },
    };
}

fn genChar(char: u8) TypVal {
    return .{
        .typ = .i8,
        .val = .{ .int = char },
    };
}

fn genBool(boo: bool) TypVal {
    return .{ .typ = .i1, .val = .{ .int = @intFromBool(boo) } };
}

fn genStr(gen: *Codegen, str: usize) !TypVal {
    const len = gen.str_lens.items[str];
    const tmp1 = gen.newTmp();
    const tmp = gen.newTmp();
    try gen.print(
        \\
        \\  %{} = insertvalue %str poison, ptr @.s{}, 0
        \\  %{} = insertvalue %str %{}, i64 {}, 1
    , .{ tmp1, str, tmp, tmp1, len });

    return .{
        .typ = .{ .name = "str" },
        .val = .{ .tmp = tmp },
    };
}

fn genInferStruc(gen: *Codegen, struc: Ast.InferStruct) !TypVal {
    const name = gen.info.typs[struc.typ_id].name;
    return gen.genStructExpr(.{
        .fields = struc.fields,
        .name = name,
    });
}

fn genStructExpr(gen: *Codegen, struc: Ast.StructExpr) !TypVal {
    var val: Val = .undef;
    for (struc.fields, 0..) |field, i| {
        const typ_val = try gen.genExpr(field.expr);
        const tmp = gen.newTmp();
        try gen.print(
            "\n  %{} = insertvalue %{s} {f}, {f}, {d}",
            .{ tmp, struc.name, val, typ_val, i },
        );
        val = .{ .tmp = tmp };
    }
    return .{
        .typ = .{ .name = struc.name },
        .val = val,
    };
}

fn genBinary(gen: *Codegen, binary: Ast.Binary) !TypVal {
    const left = try gen.genExpr(binary.left);
    const right = try gen.genExpr(binary.right);
    const tmp = gen.newTmp();
    try gen.print("\n  %{} = ", .{tmp});
    try gen.genBinOp(binary.kind);
    try gen.print(" {f}, {f}", .{ left, right.val });
    return .{
        .typ = binOpRetTyp(binary.kind, left.typ),
        .val = .{ .tmp = tmp },
    };
}

fn binOpRetTyp(kind: Ast.Binary.Kind, child_typ: Typ) Typ {
    switch (kind) {
        .sub, .add, .mul, .div, .rem, .andb, .orb => return child_typ,
        .equ, .les => return .i1,
    }
}

fn genBinOp(gen: *Codegen, kind: Ast.Binary.Kind) !void {
    switch (kind) {
        .orb => try gen.print("or", .{}),
        .andb => try gen.print("and", .{}),
        .add => try gen.print("add", .{}),
        .sub => try gen.print("sub", .{}),
        .mul => try gen.print("mul", .{}),
        .div => try gen.print("sdiv", .{}),
        .rem => try gen.print("srem", .{}),
        .equ => try gen.print("icmp eq", .{}),
        .les => try gen.print("icmp slt", .{}),
    }
}

fn genVar(gen: *Codegen, name: []const u8) !TypVal {
    const ref = gen.vars.get(name).?;
    return gen.loadTypVal(ref);
}

fn print(gen: *Codegen, comptime fmt: []const u8, args: anytype) !void {
    try gen.writer.interface.print(fmt, args);
}

const Error = error{ WriteFailed, OutOfMemory };

fn deinit(gen: *Codegen) void {
    gen.fun_ret_typs.deinit();
    gen.vars.deinit();
    gen.file.close(gen.io);
    gen.str_lens.deinit(gen.gpa);
    var structs = gen.structs.valueIterator();
    while (structs.next()) |struc| {
        struc.fields.deinit();
    }
    gen.structs.deinit();
    gen.llvm_typs.deinit();
    gen.loop_ends.deinit(gen.gpa);
    gen.* = undefined;
}
