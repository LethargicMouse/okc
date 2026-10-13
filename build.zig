const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "okc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const zlinter = @import("zlinter");
    const lint_cmd = b.step("lint", "Lint source code.");
    const lint_step = step: {
        var builder = zlinter.builder(b, .{});
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".field_values) |field_value| {
            const rule: zlinter.BuiltinLintRule = @fromBackingInt(field_value);
            if (rule == .require_doc_comment or
                rule == .no_inferred_error_unions or
                rule == .no_global_vars)
            {
                continue;
            }
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    };
    lint_step.dependOn(&run_exe_tests.step);
    lint_cmd.dependOn(lint_step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(lint_cmd);
}
