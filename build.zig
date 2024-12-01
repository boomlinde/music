const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    addExe(b, "pdsynth", "src/main_pdsynth.zig", target, optimize, &.{ "sdl2", "jack" });
    addExe(b, "drummer", "src/main_drummer.zig", target, optimize, &.{ "sdl2", "jack" });
    addExe(b, "autoconnect", "src/main_autoconnect.zig", target, optimize, &.{"jack"});
    addExe(b, "jack-mt32", "src/main_mt32.zig", target, optimize, &.{ "jack", "mt32emu", "sdl2" });
    addExe(b, "jack-activesensing", "src/main_activesensing.zig", target, optimize, &.{"jack"});
}

fn addExe(
    b: *std.Build,
    comptime name: []const u8,
    comptime src_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    libs: []const []const u8,
) void {
    const exe = withLibs(b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(src_path),
        .target = target,
        .optimize = optimize,
    }), libs);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run-" ++ name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = withLibs(b.addTest(.{
        .root_source_file = b.path(src_path),
        .target = target,
        .optimize = optimize,
    }), libs);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test-" ++ name, "Run " ++ name ++ " unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    if (b.args) |args| run_cmd.addArgs(args);
}

fn withLibs(step: *std.Build.Step.Compile, libs: []const []const u8) *std.Build.Step.Compile {
    for (libs) |lib| step.linkSystemLibrary(lib);
    step.linkLibC();
    return step;
}
