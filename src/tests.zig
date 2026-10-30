const std = @import("std");

const okc = @import("okc");

fn testFile(comptime name: []const u8, output: []const u8) !void {
    const ok_path = std.fmt.comptimePrint("examples/{s}.ok", .{name});
    try okc.compile(std.testing.io, std.testing.allocator, ok_path);

    const run_res = try std.process.run(std.testing.allocator, std.testing.io, .{ .argv = &.{okc.out_path} });
    defer std.testing.allocator.free(run_res.stdout);
    defer std.testing.allocator.free(run_res.stderr);
    try std.testing.expect(run_res.term.exited == 0);
    try std.testing.expectEqualStrings(output, run_res.stdout);
}

test "Empty.ok" {
    const code = try okc.runFile(std.testing.io, std.testing.allocator, "examples/Empty.ok");
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
    try okc.compile(std.testing.io, std.testing.allocator, "examples/RawTerm.ok");
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
    try testFile("Method", "katze says six\nkatze says seven\n");
}

test "Enum.ok" {
    try testFile("Enum", "go\n");
}

test "EnumInfer.ok" {
    try testFile("EnumInfer", "go\n");
}

test "EnumArray.ok" {
    try testFile("EnumArray", "go");
}

test "Context.ok" {
    try testFile("Context", "can't launch rockets cuz I'm not evil");
}
