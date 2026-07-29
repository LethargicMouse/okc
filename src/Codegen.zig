const std = @import("std");

const Ast = @import("Ast.zig");

const Unescaped = struct { len: usize, repr: []const u8 };

const Val = union(enum) {
    int: []const u8,
    str: usize,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("i32 {s}", .{int}),
            .str => |str| try writer.print("ptr @.s{}", .{str}),
        }
    }
};

const Codegen = @This();

io: std.Io,
gpa: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,

pub fn init(io: std.Io, gpa: std.mem.Allocator, write_buf: []u8, comptime path: []const u8) !Codegen {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    const writer = file.writer(io, write_buf);
    return .{
        .io = io,
        .gpa = gpa,
        .file = file,
        .writer = writer,
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
        try gen.genExtFun(ext_fun);
    }
    for (ast.funs) |fun| {
        try gen.genFun(fun);
    }
}

fn genExtFun(gen: *Codegen, ext_fun: Ast.ExtFun) !void {
    try gen.print("\ndeclare i32 @{s}(", .{ext_fun.header.name});
    if (ext_fun.header.params.len != 0) {
        try gen.genTyp(ext_fun.header.params[0].typ);
        for (ext_fun.header.params[1..]) |param| {
            try gen.print(", ", .{});
            try gen.genTyp(param.typ);
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
    try gen.genTyp(param.typ);
    try gen.print(" {s}", .{param.name});
}

fn genTyp(gen: *Codegen, typ: Ast.Typ) !void {
    switch (typ) {
        .name => try gen.print("ptr", .{}),
        .prime => |prime| try gen.genPrime(prime),
        .ptr => try gen.print("ptr", .{}),
    }
}

fn genPrime(gen: *Codegen, prime: Ast.Prime) !void {
    switch (prime) {
        .i32 => try gen.print("i32", .{}),
        .u8 => try gen.print("u8", .{}),
    }
}

fn genStatement(gen: *Codegen, statement: Ast.Statement) !void {
    switch (statement) {
        .ret => |expr| try gen.genRet(expr),
        .call => |call| try gen.genCall(call),
    }
}

fn genCall(gen: *Codegen, call: Ast.Call) !void {
    var arg_vals = try std.ArrayList(Val).initCapacity(gen.gpa, call.args.len);
    defer arg_vals.deinit(gen.gpa);
    for (call.args) |arg| {
        const val = genExpr(arg);
        try arg_vals.append(gen.gpa, val);
    }
    try gen.print("\n  call i32 @{s}(", .{call.name});
    if (call.args.len != 0) {
        try gen.print("{f}", .{arg_vals.items[0]});
        for (arg_vals.items[1..]) |val| {
            try gen.print(", {f}", .{val});
        }
    }
    try gen.print(")", .{});
}

fn genRet(gen: *Codegen, expr: Ast.Expr) !void {
    const val = genExpr(expr);
    try gen.print("\n  ret {f}", .{val});
}

fn genExpr(expr: Ast.Expr) Val {
    switch (expr) {
        .int => |int| return .{ .int = int },
        .str => |str| return .{ .str = str },
    }
}

fn print(gen: *Codegen, comptime fmt: []const u8, args: anytype) !void {
    try gen.writer.interface.print(fmt, args);
}

fn deinit(gen: Codegen) void {
    gen.file.close(gen.io);
}
