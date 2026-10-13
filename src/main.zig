const std = @import("std");

const ast = @import("ast/mod.zig");
const Checker = @import("Checker.zig");
const Codegen = @import("Codegen.zig");
const Failer = @import("Failer.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Source = @import("Source.zig");
const Typ = @import("typ/mod.zig").Typ;

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

const more_stack_trace_frames = false;

fn run(init: std.process.Init) !u8 {
    if (more_stack_trace_frames) {
        var safe = std.heap.SafeAllocator.init(init.gpa, .{
            .stack_trace_frames = 20,
        });
        defer _ = safe.deinit();
        return runCLI(init.io, safe.allocator(), init.minimal.args);
    }
    return runCLI(init.io, init.gpa, init.minimal.args);
}

fn runCLI(io: std.Io, gpa: std.mem.Allocator, args: std.process.Args) !u8 {
    var iter = args.iterate();
    // skip exec name
    std.debug.assert(iter.skip());
    if (iter.next()) |path| {
        return runFile(io, gpa, path);
    } else {
        std.log.err("no source path given", .{});
        return error.Handled;
    }
}

const build_dir_path = "build";
const out_ll_path = build_dir_path ++ "/out.ll";
pub const out_path = build_dir_path ++ "/out";

pub fn runFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    try compile(io, gpa, path);
    return runCmd(io, &.{out_path});
}

pub fn compile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !void {
    var source = try Source.read(io, gpa, path);
    defer source.deinit(gpa);

    var lexer = try Lexer.init(gpa, source);
    const tokens = try lexer.lex(gpa);

    ast.arena = .init(gpa);
    defer ast.arena.deinit();

    Typ.memo = .init(gpa);
    defer Typ.memo.deinit();

    var parser = Parser.init(gpa, tokens);
    const module = try parser.run();

    var checker_arena = std.heap.ArenaAllocator.init(gpa);
    defer checker_arena.deinit();

    var failer = Failer.init();

    var checker = try Checker.init(
        gpa,
        &checker_arena,
        &failer,
    );
    try checker.run(module);

    std.Io.Dir.cwd().createDirPath(io, build_dir_path) catch {
        std.log.err("failed to create `" ++ build_dir_path ++ "`", .{});
        return error.Handled;
    };

    var write_buf: [4096]u8 = undefined;
    var gen = try Codegen.init(
        io,
        gpa,
        &write_buf,
        out_ll_path,
    );
    gen.run(module) catch |err| switch (err) {
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

test {
    _ = &main;
    _ = @import("tests.zig");
}
