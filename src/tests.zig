const std = @import("std");

const okc = @import("okc");

fn testFileCode(comptime name: []const u8, output: []const u8, code: u8) !void {
    const ok_path = std.fmt.comptimePrint("examples/{s}.ok", .{name});
    try okc.compile(std.testing.io, std.testing.allocator, ok_path);

    const run_res = try std.process.run(std.testing.allocator, std.testing.io, .{ .argv = &.{okc.out_path} });
    defer std.testing.allocator.free(run_res.stdout);
    defer std.testing.allocator.free(run_res.stderr);
    try std.testing.expectEqual(run_res.term.exited, code);
    try std.testing.expectEqualStrings(output, run_res.stdout);
}

fn testFile(comptime name: []const u8, output: []const u8) !void {
    try testFileCode(name, output, 0);
}

test "Empty.ok" {
    try testFileCode("Empty", "", 123);
}

test "Simple_Call.ok" {
    try testFile("Simple_Call", "hello\n");
}

test "Simple_Call_2.ok" {
    try testFile("Simple_Call_2", "123");
}

test "Var.ok" {
    try testFile("Var", "wazzup niggas\n");
}

test "Var_Assign.ok" {
    try testFile("Var_Assign", "oh gotta go nvm bye\n");
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

test "Void_Fun.ok" {
    try testFile("Void_Fun", "hello\n");
}

test "Ignore.ok" {
    try testFile("Ignore", "");
}

test "Fun_Arg.ok" {
    try testFile("Fun_Arg", "hello there\n");
}

test "Struct.ok" {
    try testFile("Struct", "six seven\n");
}

test "Raw_Term.ok" {
    try okc.compile(std.testing.io, std.testing.allocator, "examples/Raw_Term.ok");
}

test "Nest_Ret.ok" {
    try testFile("Nest_Ret", "does return\n");
}

test "Unreachable.ok" {
    try testFile("Unreachable", "reachable\n");
}

test "Infer_Struct.ok" {
    try testFile("Infer_Struct", "6-7\n");
}

test "Mut_Ptr.ok" {
    try testFile("Mut_Ptr", "six seven\n");
}

test "Comment.ok" {
    try testFile("Comment", "comments\n");
}

test "Ret_Void.ok" {
    try testFile("Ret_Void", "hello");
}

test "Nest_Var.ok" {
    try testFile("Nest_Var", "six\nseven\n");
}

test "Generic_Struct.ok" {
    try testFile("Generic_Struct", "67\n");
}

test "Slice_Elem.ok" {
    try testFile("Slice_Elem", "6-7...");
}

test "Generic_Fun.ok" {
    try testFile("Generic_Fun", "six 7\n");
}

test "Mut_Slice.ok" {
    try testFile("Mut_Slice", "6 7\n");
}

test "Fun_Ptr.ok" {
    try testFile("Fun_Ptr", "hello\n");
}

test "Array_To_Slice.ok" {
    try testFile("Array_To_Slice", "6 7");
}

test "Constant.ok" {
    try testFile("Constant", "six seven\n");
}

test "Default_Field.ok" {
    try testFile("Default_Field", "six seven\n");
}

test "Box.ok" {
    try testFile("Box", "6 7");
}

test "Infer_Int.ok" {
    try testFile("Infer_Int", "");
}

test "Typed_Array.ok" {
    try testFile("Typed_Array", "six\nseven\n");
}

test "For.ok" {
    try testFile("For", "six seven\n");
}

test "Fizzbuzz_2.ok" {
    try testFile("Fizzbuzz_2", fizzbuzz_output);
}

test "Subslice.ok" {
    try testFile("Subslice", "6\n7\n");
}

test "Type_Alias.ok" {
    try testFile("Type_Alias", "hello world");
}

test "Method.ok" {
    try testFile("Method", "katze says six\nkatze says seven\n");
}

test "Enum.ok" {
    try testFile("Enum", "go\n");
}

test "Enum_Infer.ok" {
    try testFile("Enum_Infer", "go\n");
}

test "Enum_Array.ok" {
    try testFile("Enum_Array", "go");
}

test "Context.ok" {
    try testFileCode("Context", "fatal: can't launch rockets cuz I'm not evil\n", 1);
}

test "Std.ok" {
    try testFile("../Std_Test", "hello world\none two three build/out\n");
}
