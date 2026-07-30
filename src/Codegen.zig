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
};

const Typ = enum {
    i1,
    i8,
    i32,
    ptr,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(@tagName(typ));
    }
};

const Codegen = @This();

io: std.Io,
gpa: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
fun_ret_typs: std.StringHashMap(Typ),
vars: std.StringHashMap(Var),
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
    };
}

pub fn run(gen: *Codegen, ast: Ast) !void {
    defer gen.deinit();
    try gen.genAst(ast);
    try gen.writer.flush();
}

fn genAst(gen: *Codegen, ast: Ast) !void {
    try gen.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    for (ast.strs, 0..) |str, i| {
        try gen.genStrDecl(i, str);
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

fn genStrDecl(gen: *Codegen, index: usize, str: []const u8) !void {
    const unescaped = try unescape(gen.gpa, str);
    defer gen.gpa.free(unescaped.repr);
    try gen.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
        index,
        unescaped.len + 1,
        unescaped.repr,
    });
}

fn unescape(gpa: std.mem.Allocator, str: []const u8) !Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, str.len);
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '\\' => {
                i += 1;
                switch (str[i]) {
                    'n' => try vec.append(gpa, str[i]),
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
        .len = str.len,
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
    try gen.print(") {{\nentry:", .{});
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
    }
}

fn genStatement(gen: *Codegen, statement: Ast.Statement) Error!void {
    switch (statement) {
        .ret => |expr| try gen.genRet(expr),
        .call => |call| _ = try gen.genCall(call),
        .let => |let| try gen.genLet(let),
        .assign => |assign| try gen.genAssign(assign),
        .iff => |iff| try gen.genIf(iff),
    }
}

fn genIf(gen: *Codegen, iff: Ast.If) !void {
    const condition = try gen.genExpr(iff.condition);
    const then_label = gen.newTmp();
    const else_label = gen.newTmp();
    try gen.print("\n  br {f}, label %l{}, label %l{}\nl{}:", .{
        condition,
        then_label,
        else_label,
        then_label,
    });
    for (iff.then_branch) |statement| {
        try gen.genStatement(statement);
    }
    const end_label = gen.newTmp();
    try gen.print("\n  br label %l{}\nl{}:", .{ end_label, else_label });
    for (iff.else_branch) |statement| {
        try gen.genStatement(statement);
    }
    try gen.print("\n  br label %l{}\nl{}:", .{ end_label, end_label });
}

fn genAssign(gen: *Codegen, assign: Ast.Assign) !void {
    const tmp = gen.vars.get(assign.name).?;
    const val = try gen.genExpr(assign.expr);
    try gen.storeInto(tmp.tmp, val);
}

fn genLet(gen: *Codegen, let: Ast.Let) !void {
    const typ_val = try gen.genExpr(let.expr);
    const tmp = try gen.store(typ_val);
    try gen.vars.put(let.name, tmp);
}

fn store(gen: *Codegen, typ_val: TypVal) !Var {
    const tmp = gen.newTmp();
    try gen.print("\n  %t{} = alloca {f}", .{ tmp, typ_val.typ });
    try gen.storeInto(tmp, typ_val);
    return .{ .tmp = tmp, .inner_typ = typ_val.typ };
}

fn storeInto(gen: *Codegen, tmp: u32, val: TypVal) !void {
    try gen.print("\n  store {f}, ptr %t{}", .{ val, tmp });
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
        .int => |int| return genInt(int),
        .str => |str| return genStr(str),
        .call => |call| return gen.genCall(call),
        .vari => |name| return gen.genVar(name),
        .binary => |binary| return gen.genBinary(binary.*),
    }
}

fn genInt(int: []const u8) TypVal {
    return .{
        .typ = .i32,
        .val = .{ .int = int },
    };
}

fn genStr(str: usize) TypVal {
    return .{
        .typ = .ptr,
        .val = .{ .str = str },
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
        .sub, .add, .mul, .div => return child_typ,
        .equ => return .i1,
    }
}

fn genBinOp(gen: *Codegen, bin_op: Ast.BinOp) !void {
    switch (bin_op) {
        .add => try gen.print("add", .{}),
        .sub => try gen.print("sub", .{}),
        .mul => try gen.print("mul", .{}),
        .div => try gen.print("sdiv", .{}),
        .equ => try gen.print("icmp eq", .{}),
    }
}

fn genVar(gen: *Codegen, name: []const u8) !TypVal {
    const vari = gen.vars.get(name).?;
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
}
