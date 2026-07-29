const std = @import("std");

const Ast = @import("Ast.zig");

const Val = union(enum) {
    int: []const u8,

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("i32 {s}", .{int}),
        }
    }
};

const Codegen = @This();

io: std.Io,
file: std.Io.File,
writer: std.Io.File.Writer,

pub fn init(io: std.Io, write_buf: []u8, comptime path: []const u8) !Codegen {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    const writer = file.writer(io, write_buf);
    return .{
        .io = io,
        .file = file,
        .writer = writer,
    };
}

pub fn run(gen: *Codegen, ast: Ast) !void {
    defer gen.deinit();
    try gen.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
    for (ast.funs) |fun| {
        try gen.gen_fun(fun);
    }
    try gen.writer.flush();
}

fn gen_fun(gen: *Codegen, fun: Ast.Fun) !void {
    try gen.print("\ndefine i32 @{s}() {{\nentry:", .{fun.name});
    for (fun.statements) |statement| {
        try gen.gen_statement(statement);
    }
    try gen.print("\n}}", .{});
}

fn gen_statement(gen: *Codegen, statement: Ast.Statement) !void {
    switch (statement) {
        .ret => |expr| try gen.gen_ret(expr),
    }
}

fn gen_ret(gen: *Codegen, expr: Ast.Expr) !void {
    const val = gen_expr(expr);
    try gen.print("\n  ret {f}", .{val});
}

fn gen_expr(expr: Ast.Expr) Val {
    switch (expr) {
        .int => |int| return .{ .int = int },
    }
}

fn print(gen: *Codegen, comptime fmt: []const u8, args: anytype) !void {
    try gen.writer.interface.print(fmt, args);
}

fn deinit(gen: Codegen) void {
    gen.file.close(gen.io);
}
