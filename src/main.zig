const std = @import("std");

const Ast = @import("Ast/mod.zig");
const Checker = @import("Checker.zig");
const Codegen = @import("Codegen.zig");
const Lexer = @import("Lexer.zig");
const Memo = @import("memo.zig").Memo;
const Parser = @import("Parser.zig");
const Source = @import("Source.zig");
const Typ = @import("typ.zig").Typ;

pub fn main(init: std.process.Init) u8 {
    const code = run(init) catch |err| {
        switch (err) {
            error.Handled => {},
            error.OutOfMemory => std.log.err("out of memory", .{}),
        }
        return 1;
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

    var lexer = try Lexer.init(gpa, source);
    const tokens = try lexer.lex(gpa);

    var ast_arena = std.heap.ArenaAllocator.init(gpa);
    defer ast_arena.deinit();

    var ast_typ_memo = Memo(Typ).init(&ast_arena);
    defer ast_typ_memo.deinit();

    var parser = Parser.init(gpa, &ast_arena, &ast_typ_memo, tokens);
    const ast = try parser.run();

    var checker_arena = std.heap.ArenaAllocator.init(gpa);
    defer checker_arena.deinit();

    var checker_failer = Checker.Failer.init();

    var checker = try Checker.init(gpa, &checker_arena, &ast_typ_memo, &checker_failer);
    const items = try checker.run(ast);

    std.Io.Dir.cwd().createDirPath(io, build_dir_path) catch {
        std.log.err("failed to create `" ++ build_dir_path ++ "`", .{});
        return error.Handled;
    };

    var write_buf: [256]u8 = undefined;
    var gen = try Codegen.init(io, gpa, &ast_typ_memo, items, &write_buf, out_ll_path);
    gen.run() catch |err| switch (err) {
        error.WriteFailed => {
            std.log.err("failed to write to `" ++ out_ll_path ++ "`", .{});
            return error.Handled;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };

    const code = try runCmd(io, &.{ "clang", "-o", out_path, out_ll_path });
    // `Checker` should prevent incorrect IR
    std.debug.assert(code == 0);
}

fn runCmd(io: std.Io, argv: []const []const u8) !u8 {
    var child = std.process.spawn(io, .{ .argv = argv }) catch {
        std.log.err("failed to run `{f}`", .{ConcatStr(" "){ .items = argv }});
        return error.Handled;
    };
    const term = child.wait(io) catch {
        std.log.err("failed to wait for `{f}`", .{ConcatStr(" "){ .items = argv }});
        return error.Handled;
    };
    return switch (term) {
        .exited => |code| code,
        .signal, .stopped, .unknown => 1,
    };
}

fn ConcatStr(sep: []const u8) type {
    return struct {
        items: []const []const u8,

        pub fn format(self: @This(), writer: *std.Io.Writer) !void {
            if (self.items.len != 0) {
                try writer.writeAll(self.items[0]);
                for (self.items[1..]) |item| {
                    try writer.print("{s}{s}", .{ sep, item });
                }
            }
        }
    };
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

test "Empty.ok" {
    const code = try runFile(std.testing.io, std.testing.allocator, "examples/Empty.ok");
    try std.testing.expectEqual(123, code);
}

test "SimpleCall.ok" {
    try testFile("SimpleCall", "hello\n");
}

test "SimpleCall2.ok" {
    try testFile("SimpleCall2", "123");
}

test "Var.ok" {
    try testFile("Var", "wazzup niggas\n");
}

test "VarAssign.ok" {
    try testFile("VarAssign", "oh gotta go nvm bye\n");
}

test "Arith.ok" {
    try testFile("Arith", "1");
}

test "If.ok" {
    try testFile("If", "SIXSEVEEEN!\n");
}

const fizzbuzz_output =
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
;

test "Fizzbuzz.ok" {
    try testFile(
        "Fizzbuzz",
        fizzbuzz_output,
    );
}

test "Str.ok" {
    try testFile("Str", "6-7!!!\n");
}

test "VoidFun.ok" {
    try testFile("VoidFun", "hello\n");
}

test "Ignore.ok" {
    try testFile("Ignore", "");
}

test "FunArg.ok" {
    try testFile("FunArg", "hello there\n");
}

test "Struct.ok" {
    try testFile("Struct", "six seven\n");
}

test "RawTerm.ok" {
    try compile(std.testing.io, std.testing.allocator, "examples/RawTerm.ok");
}

test "NestRet.ok" {
    try testFile("NestRet", "does return\n");
}

test "Unreachable.ok" {
    try testFile("Unreachable", "reachable\n");
}

test "InferStruct.ok" {
    try testFile("InferStruct", "6-7\n");
}

test "MutPtr.ok" {
    try testFile("MutPtr", "six seven\n");
}

test "Comment.ok" {
    try testFile("Comment", "comments\n");
}

test "RetVoid.ok" {
    try testFile("RetVoid", "hello");
}

test "NestVar.ok" {
    try testFile("NestVar", "six\nseven\n");
}

test "GenericStruct.ok" {
    try testFile("GenericStruct", "67\n");
}

test "SliceElem.ok" {
    try testFile("SliceElem", "6-7...");
}

test "GenericFun.ok" {
    try testFile("GenericFun", "six 7\n");
}

test "MutSlice.ok" {
    try testFile("MutSlice", "6 7\n");
}

test "FnPtr.ok" {
    try testFile("FnPtr", "hello\n");
}

test "ArrayToSlice.ok" {
    try testFile("ArrayToSlice", "6 7");
}

test "Constant.ok" {
    try testFile("Constant", "six seven\n");
}

test "DefaultField.ok" {
    try testFile("DefaultField", "six seven\n");
}

test "Box.ok" {
    try testFile("Box", "6 7");
}

test "InferInt.ok" {
    try testFile("InferInt", "");
}

test "TypedArray.ok" {
    try testFile("TypedArray", "six\nseven\n");
}

test "For.ok" {
    try testFile("For", "six seven\n");
}

test "Fizzbuzz2.ok" {
    try testFile("Fizzbuzz2", fizzbuzz_output);
}

test "Subslice.ok" {
    try testFile("Subslice", "6\n7\n");
}

test "TypeAlias.ok" {
    try testFile("TypeAlias", "hello world");
}

test "Method.ok" {
    try testFile("Method", "kitkat says six\nkitkat says seven\n");
}
