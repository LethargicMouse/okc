const std = @import("std");

const Codegen = @import("Codegen.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Source = @import("Source.zig");
const Checker = @import("Checker.zig");

pub fn main(init: std.process.Init) !u8 {
    const code = run(init) catch |err| switch (err) {
        error.Handled => return 1,
        else => return err,
    };
    return code;
}

fn run(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    // skip exec name
    _ = args.skip();
    if (args.next()) |path| {
        return runFile(init.io, init.gpa, path);
    } else {
        std.log.err("no source path given", .{});
        return error.Handled;
    }
}

const build_dir_path = "build";
const out_ll_path = build_dir_path ++ "/out.ll";
const out_path = build_dir_path ++ "/out";

fn runFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    try compile(io, gpa, path);
    return runCmd(io, &.{out_path});
}

fn compile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !void {
    var source = try Source.read(io, gpa, path);
    defer source.deinit(gpa);

    var lexer = try Lexer.init(gpa, &source);
    const tokens = try lexer.lex(gpa);

    var parser = Parser.init(gpa, tokens);
    const parse_result = try parser.run();
    var ast = parse_result[0];
    defer ast.deinit();
    const ast_info = parse_result[1];

    var checker = try Checker.init(gpa, ast_info);
    const info = try checker.run(ast);

    try std.Io.Dir.cwd().createDirPath(io, build_dir_path);

    var write_buf: [256]u8 = undefined;
    var gen = try Codegen.init(io, gpa, &write_buf, out_ll_path, info);
    try gen.run(ast);

    const code = try runCmd(io, &.{ "clang", "-o", out_path, out_ll_path });
    // `Checker` should prevent incorrect IR
    std.debug.assert(code == 0);
}

fn runCmd(io: std.Io, comptime argv: []const []const u8) !u8 {
    var child = try std.process.spawn(io, .{ .argv = argv });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| return code,
        else => return 1,
    }
}

fn testFile(comptime name: []const u8, output: []const u8) !void {
    const ok = std.fmt.comptimePrint("examples/{s}.ok", .{name});
    try compile(std.testing.io, std.testing.allocator, ok);

    const run_res = try std.process.run(std.testing.allocator, std.testing.io, .{ .argv = &.{out_path} });
    defer std.testing.allocator.free(run_res.stdout);
    defer std.testing.allocator.free(run_res.stderr);
    try std.testing.expect(run_res.term.exited == 0);
    try std.testing.expectEqualStrings(output, run_res.stdout);
}

test "empty.ok" {
    const code = try runFile(std.testing.io, std.testing.allocator, "examples/empty.ok");
    try std.testing.expectEqual(123, code);
}

test "simple_call.ok" {
    try testFile("simple_call", "hello\n");
}

test "simple_call_2.ok" {
    try testFile("simple_call_2", "123");
}

test "var.ok" {
    try testFile("var", "wazzup niggas\n");
}

test "var_assign.ok" {
    try testFile("var_assign", "oh gotta go nvm bye\n");
}

test "arith.ok" {
    try testFile("arith", "1");
}

test "if.ok" {
    try testFile("if", "SIXSEVEEEN!\n");
}

test "fizzbuzz.ok" {
    try testFile("fizzbuzz",
        \\1
        \\2
        \\fizz
        \\4
        \\buzz
        \\fizz
        \\7
        \\8
        \\fizz
        \\buzz
        \\11
        \\fizz
        \\13
        \\14
        \\fizzbuzz
        \\16
        \\17
        \\fizz
        \\19
        \\buzz
        \\
    );
}

test "str.ok" {
    try testFile("str", "6-7!!!\n");
}

test "void_fun.ok" {
    try testFile("void_fun", "hello\n");
}

test "ignore.ok" {
    try testFile("ignore", "");
}

test "fun_arg.ok" {
    try testFile("fun_arg", "hello there\n");
}

test "struct.ok" {
    try testFile("struct", "six seven\n");
}

test "raw_term.ok" {
    try compile(std.testing.io, std.testing.allocator, "examples/raw_term.ok");
}

test "nest_ret.ok" {
    try testFile("nest_ret", "does return\n");
}

test "unreachable.ok" {
    try testFile("unreachable", "reachable\n");
}
