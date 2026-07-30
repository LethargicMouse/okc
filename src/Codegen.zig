const std = @import("std");

const Ast = @import("Ast.zig");

const Unescaped = struct { len: usize, repr: []const u8 };

const Val = union(enum) {
    int: []const u8,
    str: usize,
    tmp: Tmp,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("i32 {s}", .{int}),
            .str => |str| try writer.print("ptr @.s{}", .{str}),
            .tmp => |tmp| try writer.print("{f} %t{}", .{ tmp.typ, tmp.number }),
        }
    }

    fn typ(val: Val) Typ {
        switch (val) {
            .int => return .i32,
            .str => return .ptr,
            .tmp => |tmp| return tmp.typ,
        }
    }
};

const Tmp = struct {
    number: u32,
    typ: Typ,
};

const Var = struct {
    tmp: u32,
    inner_typ: Typ,
};

const Typ = enum {
    i8,
    i32,
    ptr,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .i8 => try writer.writeAll("i8"),
            .i32 => try writer.writeAll("i32"),
            .ptr => try writer.writeAll("ptr"),
        }
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
        try gen.genStr(i, str);
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

fn genStr(gen: *Codegen, index: usize, str: []const u8) !void {
    const unescaped = try unescape(gen.gpa, str);
    defer gen.gpa.free(unescaped.repr);
    try gen.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\", align 1", .{
        index,
        unescaped.len,
        unescaped.repr,
    });
}

fn unescape(gpa: std.mem.Allocator, str: []const u8) !Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, str.len);
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        switch (str[i]) {
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

fn genStatement(gen: *Codegen, statement: Ast.Statement) !void {
    switch (statement) {
        .ret => |expr| try gen.genRet(expr),
        .call => |call| _ = try gen.genCall(call),
        .let => |let| try gen.genLet(let),
        .assign => |assign| try gen.genAssign(assign),
    }
}

fn genAssign(gen: *Codegen, assign: Ast.Assign) !void {
    const tmp = gen.vars.get(assign.name).?;
    const val = try gen.genExpr(assign.expr);
    try gen.storeInto(tmp.tmp, val);
}

fn genLet(gen: *Codegen, let: Ast.Let) !void {
    const val = try gen.genExpr(let.expr);
    const tmp = try gen.store(val);
    try gen.vars.put(let.name, tmp);
}

fn store(gen: *Codegen, val: Val) !Var {
    const tmp = gen.newTmp();
    try gen.print("\n  %t{} = alloca {f}", .{ tmp, val.typ() });
    try gen.storeInto(tmp, val);
    return .{ .tmp = tmp, .inner_typ = val.typ() };
}

fn storeInto(gen: *Codegen, tmp: u32, val: Val) !void {
    try gen.print("\n  store {f}, ptr %t{}", .{ val, tmp });
}

fn genCall(gen: *Codegen, call: Ast.Call) !Val {
    var arg_vals = try std.ArrayList(Val).initCapacity(gen.gpa, call.args.len);
    defer arg_vals.deinit(gen.gpa);
    for (call.args) |arg| {
        const val = try gen.genExpr(arg);
        try arg_vals.append(gen.gpa, val);
    }
    const ret_tmp = gen.newTmp();
    try gen.print("\n  %t{} = call ", .{ret_tmp});
    const ret_typ = gen.fun_ret_typs.get(call.name).?;
    try gen.print("{f} @{s}(", .{ ret_typ, call.name });
    if (call.args.len != 0) {
        try gen.print("{f}", .{arg_vals.items[0]});
        for (arg_vals.items[1..]) |val| {
            try gen.print(", {f}", .{val});
        }
    }
    try gen.print(")", .{});
    return .{ .tmp = .{ .number = ret_tmp, .typ = ret_typ } };
}

fn newTmp(gen: *Codegen) u32 {
    gen.next_tmp += 1;
    return gen.next_tmp - 1;
}

fn genRet(gen: *Codegen, expr: Ast.Expr) !void {
    const val = try gen.genExpr(expr);
    try gen.print("\n  ret {f}", .{val});
}

fn genExpr(gen: *Codegen, expr: Ast.Expr) Error!Val {
    switch (expr) {
        .int => |int| return .{ .int = int },
        .str => |str| return .{ .str = str },
        .call => |call| return gen.genCall(call),
        .vari => |name| return gen.genVar(name),
    }
}

fn genVar(gen: *Codegen, name: []const u8) !Val {
    const vari = gen.vars.get(name).?;
    const load_tmp = gen.newTmp();
    try gen.print("\n  %t{} = load {f}, ptr %t{}", .{ load_tmp, vari.inner_typ, vari.tmp });
    return .{ .tmp = .{ .number = load_tmp, .typ = vari.inner_typ } };
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
