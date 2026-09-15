const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "dagger_codegen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the generator").dependOn(&run_cmd.step);

    // The generator as a library, for the snapshot tests.
    const codegen = b.createModule(.{
        .root_source_file = b.path("src/codegen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const snapshot_module = struct {
        fn create(bb: *std.Build, root: []const u8, lib: *std.Build.Module, t: std.Build.ResolvedTarget, o: std.builtin.OptimizeMode) *std.Build.Module {
            const m = bb.createModule(.{ .root_source_file = bb.path(root), .target = t, .optimize = o });
            m.addImport("codegen", lib);
            return m;
        }
    }.create;

    const test_step = b.step("test", "Run unit and snapshot tests");
    const unit_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    const golden_tests = b.addTest(.{ .root_module = snapshot_module(b, "test/golden.zig", codegen, target, optimize) });
    test_step.dependOn(&b.addRunArtifact(golden_tests).step);

    const updater = b.addExecutable(.{
        .name = "update_snapshots",
        .root_module = snapshot_module(b, "test/update_snapshots.zig", codegen, target, optimize),
    });
    const update = b.addRunArtifact(updater);
    update.setCwd(b.path("test"));
    b.step("update-snapshots", "Rewrite test/snapshots from the current generator").dependOn(&update.step);
}
