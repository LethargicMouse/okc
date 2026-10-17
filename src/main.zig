const std = @import("std");

pub const Codegen = @import("Codegen.zig");
pub const ConcatStr = @import("ConcatStr.zig");
pub const Expr = @import("Expr.zig");
pub const Failer = @import("Failer.zig");
pub const HashMap = @import("hash_map.zig").HashMap;
pub const Item = @import("Item.zig");
pub const Layout = @import("Layout.zig");
pub const Lexeme = @import("lexeme.zig").Lexeme;
pub const Lexer = @import("Lexer.zig");
pub const Location = @import("Location.zig");
pub const Memo = @import("memo.zig").Memo;
pub const Module = @import("Module.zig");
pub const Parser = @import("Parser.zig");
pub const Pos = @import("Pos.zig");
pub const PtrHashMap = @import("ptr_hash_map.zig").PtrHashMap;
pub const SliceHashMap = @import("slice_hash_map.zig").SliceHashMap;
pub const Source = @import("Source.zig");
pub const Stmt = @import("Stmt.zig");
pub const Typ = @import("typ.zig").Typ;
pub const Val = @import("val.zig").Val;

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

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    Typ.memo = .init(gpa);
    defer Typ.memo.deinit();

    var parser = Parser.init(gpa, arena.allocator(), tokens);
    const module = try parser.run();

    var failer: Failer = .init();
    try module.check(gpa, arena.allocator(), &failer);
    try failer.ensureNoErrors();

    std.Io.Dir.cwd().createDirPath(io, build_dir_path) catch {
        std.log.err("failed to create `" ++ build_dir_path ++ "`", .{});
        return error.Handled;
    };

    var write_buf: [4096]u8 = undefined;
    var gen = try Codegen.init(io, gpa, arena.allocator(), &write_buf, out_ll_path);
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
        std.log.err("failed to run `{f}`", .{ConcatStr{ .items = argv }});
        return error.Handled;
    };
    const term = child.wait(io) catch {
        std.log.err("failed to wait for `{f}`", .{ConcatStr{ .items = argv }});
        return error.Handled;
    };
    return switch (term) {
        .exited => |code| code,
        .signal, .stopped, .unknown => 1,
    };
}

// numbered to enable `<`
pub const ControlFlow = enum(u2) {
    cont = 0,
    brek = 1,
    ret = 2,
};

test {
    _ = &main;
    _ = @import("tests.zig");
}
