const std = @import("std");

const Ast = @import("Ast.zig");

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

    fn toVar(typ_val: TypVal) Var {
        std.debug.assert(typ_val.typ == .name);
        return .{ .inner_typ = typ_val.typ, .tmp = typ_val.val.tmp };
    }
};

const Val = union(enum) {
    int: []const u8,
    str: usize,
    tmp: u32,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("{s}", .{int}),
            .str => |str| try writer.print("@.s{}", .{str}),
            .tmp => |tmp| try writer.print("%t{}", .{tmp}),
        }
    }
};

const Var = struct {
    tmp: u32,
    inner_typ: Typ,

    fn toTypVar(vari: Var) TypVal {
        std.debug.assert(vari.inner_typ == .name);
        return .{ .typ = vari.inner_typ, .val = .{ .tmp = vari.tmp } };
    }
};

const Typ = union(enum) {
    name: []const u8,
    i1,
    i8,
    i32,
    i64,
    ptr,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .name => |name| try writer.print("%{s}", .{name}),
            else => try writer.writeAll(@tagName(typ)),
        }
    }
};

const Field = struct {
    index: u32,
    typ: Typ,
};

const Struct = struct {
    fields: std.StringHashMap(Field),
};

const Codegen = @This();

io: std.Io,
gpa: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
fun_ret_typs: std.StringHashMap(Typ),
vars: std.StringHashMap(Var),
structs: std.StringHashMap(Struct),
str_lens: std.ArrayList(usize) = .empty,
next_tmp: u32 = 0,

pub fn init(io: std.Io, gpa: std.mem.Allocator, write_buf: []u8, comptime path: []const u8) !Codegen {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    return .{
        .io = io,
        .gpa = gpa,
        .file = file,
        .writer = file.writer(io, write_buf),
        .fun_ret_typs = std.StringHashMap(Typ).init(gpa),
        .vars = std.StringHashMap(Var).init(gpa),
        .structs = std.StringHashMap(Struct).init(gpa),
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
    for (ast.ext_funs) |ext_fun| {
        try gen.registerHeader(ext_fun.header);
    }
    for (ast.funs) |fun| {
        try gen.registerHeader(fun.header);
    }
    for (ast.ext_funs) |ext_fun| {
        try gen.genExtFun(ext_fun);
    }
    for (ast.funs) |fun| {
        try gen.genFun(fun);
    }
    try gen.print("\n", .{});
}

fn genStrStruct(gen: *Codegen) !void {
    try gen.print("\n%str = type {{ ptr, i64 }}", .{});
    var struc = Struct{
        .fields = std.StringHashMap(Field).init(gen.gpa),
    };
    try struc.fields.put("ptr", .{ .typ = .ptr, .index = 0 });
    try struc.fields.put("len", .{ .typ = .i64, .index = 1 });
    try gen.structs.put("str", struc);
}

fn registerHeader(gen: *Codegen, header: Ast.Header) !void {
    const typ = genTyp(header.ret_typ);
    try gen.fun_ret_typs.put(header.name, typ);
}

fn genExtFun(gen: *Codegen, ext_fun: Ast.ExtFun) !void {
    try gen.print("\ndeclare i32 @{s}(", .{ext_fun.header.name});
    if (ext_fun.header.params.len != 0) {
        const first_typ = genTyp(ext_fun.header.params[0].typ);
        try gen.print("{f}", .{first_typ});
        for (ext_fun.header.params[1..]) |param| {
            const typ = genTyp(param.typ);
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
                    else => {
                        std.log.err("bad escape symbol: `\\{}`", .{str[i]});
                        // supposed to be checked by `Analyser`
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
    try gen.print("\ndefine i32 @{s}(", .{fun.header.name});
    if (fun.header.params.len != 0) {
        try gen.genParam(fun.header.params[0]);
        for (fun.header.params[1..]) |param| {
            try gen.print(", ", .{});
            try gen.genParam(param);
        }
    }
    try gen.print(
        \\) {{
        \\entry:
    , .{});
    for (fun.statements) |statement| {
        try gen.genStatement(statement);
    }
    try gen.print("\n}}", .{});
}

fn genParam(gen: *Codegen, param: Ast.Param) !void {
    const typ = genTyp(param.typ);
    try gen.print("{f} {s}", .{ typ, param.name });
}

fn genTyp(typ: Ast.Typ) Typ {
    switch (typ) {
        .name => return .ptr,
        .prime => |prime| return genPrime(prime),
        .ptr => return .ptr,
    }
}

fn genPrime(prime: Ast.Prime) Typ {
    switch (prime) {
        .i32 => return .i32,
        .u8 => return .i8,
        .u64 => return .i64,
        .bool => return .i1,
    }
}

fn genStatement(gen: *Codegen, statement: Ast.Statement) Error!void {
    switch (statement) {
        .ret => |expr| try gen.genRet(expr),
        .expr => |expr| _ = try gen.genExpr(expr),
        .let => |let| try gen.genLet(let),
        .assign => |assign| try gen.genAssign(assign),
        .iff => |iff| try gen.genIf(iff),
        .whi => |whi| try gen.genWhile(whi),
    }
}

fn genWhile(gen: *Codegen, whi: Ast.While) !void {
    const condition_label = gen.newTmp();
    try gen.uncond(condition_label, condition_label);
    try gen.genBranch(whi.branch, condition_label);
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
    try gen.genBranch(
        iff.branch,
        end_label,
    );
    for (iff.else_ifs) |branch| {
        try gen.genBranch(
            branch,
            end_label,
        );
    }
    for (iff.else_branch) |statement| {
        try gen.genStatement(statement);
    }
    try gen.uncond(end_label, end_label);
}

fn genBranch(gen: *Codegen, branch: Ast.Branch, end_label: u32) !void {
    const condition = try gen.genExpr(branch.condition);
    const then_label = gen.newTmp();
    const else_label = gen.newTmp();
    try gen.cond(condition.val, then_label, else_label);
    for (branch.statements) |statement| {
        try gen.genStatement(statement);
    }
    try gen.uncond(end_label, else_label);
}

fn genAssign(gen: *Codegen, assign: Ast.Assign) !void {
    const vari = gen.vars.get(assign.name).?;
    const typ_val = try gen.genExpr(assign.expr);
    try gen.storeInto(vari.tmp, typ_val);
}

fn genLet(gen: *Codegen, let: Ast.Let) !void {
    const typ_val = try gen.genExpr(let.expr);
    const tmp = try gen.toStack(typ_val);
    try gen.vars.put(let.name, tmp);
}

fn toStack(gen: *Codegen, typ_val: TypVal) !Var {
    if (typ_val.typ == .name) {
        return typ_val.toVar();
    }
    const tmp = gen.newTmp();
    try gen.print("\n  %t{} = alloca {f}", .{ tmp, typ_val.typ });
    try gen.storeInto(tmp, typ_val);
    return .{ .tmp = tmp, .inner_typ = typ_val.typ };
}

fn storeInto(gen: *Codegen, tmp: u32, typ_val: TypVal) !void {
    if (typ_val.typ == .name) {
        const loaded = try gen.load(typ_val.typ, typ_val.val.tmp);
        try gen.print("\n  store %{s} %t{}, ptr %t{}", .{
            typ_val.typ.name,
            loaded,
            tmp,
        });
    } else {
        try gen.print("\n  store {f}, ptr %t{}", .{ typ_val, tmp });
    }
}

fn genCall(gen: *Codegen, call: Ast.Call) !TypVal {
    var arg_typ_vals = try std.ArrayList(TypVal).initCapacity(gen.gpa, call.args.len);
    defer arg_typ_vals.deinit(gen.gpa);
    for (call.args) |arg| {
        const typ_val = try gen.genExpr(arg);
        try arg_typ_vals.append(gen.gpa, typ_val);
    }
    const ret_tmp = gen.newTmp();
    try gen.print("\n  %t{} = call ", .{ret_tmp});
    const ret_typ = gen.fun_ret_typs.get(call.name).?;
    try gen.print("{f} @{s}(", .{ ret_typ, call.name });
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

fn genRet(gen: *Codegen, expr: Ast.Expr) !void {
    const val = try gen.genExpr(expr);
    try gen.print("\n  ret {f}", .{val});
}

fn genExpr(gen: *Codegen, expr: Ast.Expr) Error!TypVal {
    switch (expr) {
        .literal_loc => |literal_loc| return gen.genLiteral(literal_loc.literal),
        .call => |call| return gen.genCall(call),
        .binary => |binary| return gen.genBinary(binary.*),
        .field => |field| return gen.genField(field.*),
    }
}

fn genLiteral(gen: *Codegen, literal: Ast.Literal) !TypVal {
    switch (literal) {
        .int => |int| return genInt(int),
        .str => |str| return gen.genStr(str),
        .vari => |name| return gen.genVar(name),
    }
}

fn genField(gen: *Codegen, field: Ast.Field) !TypVal {
    // we use genExpr and not genExprRef
    // cuz the latter evals to the former for structs
    // and we expect a struct
    const typ_val = try gen.genExpr(field.expr);
    const struc = gen.structs.get(typ_val.typ.name).?;
    const fiel = struc.fields.get(field.name).?;
    const ptr_tmp = gen.newTmp();
    try gen.print(
        "\n  %t{} = getelementptr inbounds %{s}, ptr %t{}, i32 0, i32 {}",
        .{ ptr_tmp, typ_val.typ.name, typ_val.val.tmp, fiel.index },
    );
    const tmp = try gen.load(fiel.typ, ptr_tmp);
    return .{
        .typ = fiel.typ,
        .val = .{ .tmp = tmp },
    };
}

fn load(gen: *Codegen, typ: Typ, from: u32) !u32 {
    const to = gen.newTmp();
    try gen.print("\n  %t{} = load {f}, ptr %t{}", .{ to, typ, from });
    return to;
}

fn genInt(int: []const u8) TypVal {
    return .{
        .typ = .i32,
        .val = .{ .int = int },
    };
}

fn genStr(gen: *Codegen, str: usize) !TypVal {
    const len = gen.str_lens.items[str];
    const tmp = gen.newTmp();
    try gen.print(
        \\
        \\  %t{} = alloca %str, align 8
        \\  store %str {{ ptr @.s{}, i64 {} }}, ptr %t{}
    , .{ tmp, str, len, tmp });
    return .{
        .typ = .{ .name = "str" },
        .val = .{ .tmp = tmp },
    };
}

fn genBinary(gen: *Codegen, binary: Ast.Binary) !TypVal {
    const left = try gen.genExpr(binary.left);
    const right = try gen.genExpr(binary.right);
    const tmp = gen.newTmp();
    try gen.print("\n  %t{} = ", .{tmp});
    try gen.genBinOp(binary.op);
    try gen.print(" {f}, {f}", .{ left, right.val });
    return .{
        .typ = binOpRetTyp(binary.op, left.typ),
        .val = .{ .tmp = tmp },
    };
}

fn binOpRetTyp(bin_op: Ast.BinOp, child_typ: Typ) Typ {
    switch (bin_op) {
        .sub, .add, .mul, .div, .rem => return child_typ,
        .equ, .les => return .i1,
    }
}

fn genBinOp(gen: *Codegen, bin_op: Ast.BinOp) !void {
    switch (bin_op) {
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
    const vari = gen.vars.get(name).?;
    if (vari.inner_typ == .name) {
        return vari.toTypVar();
    }
    const load_tmp = gen.newTmp();
    try gen.print("\n  %t{} = load {f}, ptr %t{}", .{ load_tmp, vari.inner_typ, vari.tmp });
    return .{
        .typ = vari.inner_typ,
        .val = .{ .tmp = load_tmp },
    };
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
    gen.* = undefined;
}
