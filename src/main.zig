const std = @import("std");

const Codegen = @import("Codegen.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Source = @import("Source.zig");

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

const build_dir = "build";
const out_ll = build_dir ++ "/out.ll";
const out = build_dir ++ "/out";

fn runFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    try compile(io, gpa, path, out_ll);
    return runCmd(io, &.{out});
}

fn compile(io: std.Io, gpa: std.mem.Allocator, path: []const u8, comptime out_path: []const u8) !void {
    var source = try Source.read(io, gpa, path);
    defer source.deinit(gpa);

    var lexer = try Lexer.init(gpa, source);
    const tokens = try lexer.lex(gpa);

    var parser = Parser.init(gpa, tokens);
    var ast = try parser.run();
    defer ast.deinit();

    try std.Io.Dir.cwd().createDirPath(io, build_dir);

    var write_buf: [256]u8 = undefined;
    var gen = try Codegen.init(io, gpa, &write_buf, out_path);
    try gen.run(ast);

    const code = try runCmd(io, &.{ "clang", "-o", out, out_path });
    // `Analyser` should prevent incorrect IR
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

fn testFile(comptime name: []const u8) !void {
    const ok = std.fmt.comptimePrint("examples/{s}.ok", .{name});
    const ll = std.fmt.comptimePrint("examples_compiled/{s}.ll", .{name});
    const test_out_ll = std.fmt.comptimePrint("build/out_{s}.ll", .{name});

    try compile(std.testing.io, std.testing.allocator, ok, test_out_ll);

    const dir = std.Io.Dir.cwd();

    const expected = dir.readFileAlloc(std.testing.io, ll, std.testing.allocator, .unlimited) catch {
        std.log.err("failed to read `{s}`", .{ll});
        return error.Handled;
    };
    defer std.testing.allocator.free(expected);

    const found = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, test_out_ll, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(found);

    try std.testing.expectEqualStrings(expected, found);
}

test "empty.ok" {
    try testFile("empty");
}

test "simple_call.ok" {
    try testFile("simple_call");
}

test "simple_call_2.ok" {
    try testFile("simple_call_2");
}

test "var.ok" {
    try testFile("var");
}

test "var_assign.ok" {
    try testFile("var_assign");
}

test "arith.ok" {
    try testFile("arith");
}

test "if.ok" {
    try testFile("if");
}

test "fizzbuzz.ok" {
    try testFile("fizzbuzz");
}
