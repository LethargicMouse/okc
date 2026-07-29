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
        return run_file(init.io, init.gpa, path);
    } else {
        std.log.err("no source path given", .{});
        return error.Handled;
    }
}

fn run_file(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    var source = try Source.read(io, gpa, path);
    defer source.deinit(gpa);

    var lexer = try Lexer.init(gpa, source);
    const tokens = try lexer.lex(gpa);

    var parser = Parser.init(gpa, tokens);
    var ast = try parser.run();
    defer ast.deinit(gpa);

    const build_dir = "build";
    try std.Io.Dir.cwd().createDirPath(io, build_dir);

    var write_buf: [256]u8 = undefined;
    const out_ll = build_dir ++ "/out.ll";
    var gen = try Codegen.init(io, &write_buf, out_ll);
    try gen.run(ast);

    const out = build_dir ++ "/out";
    _ = try run_cmd(io, &.{ "clang", "-o", out, out_ll });
    return run_cmd(io, &.{out});
}

fn run_cmd(io: std.Io, comptime argv: []const []const u8) !u8 {
    var child = try std.process.spawn(io, .{ .argv = argv });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| return code,
        else => return 1,
    }
}
