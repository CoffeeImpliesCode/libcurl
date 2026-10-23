// SPDX-License-Identifier: curl
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Build wiring for the separate `consumer/` package.
//!
//! This package exists to prove one thing: that a dependent needs only
//! `dep.module("libcurl")` and gets a working, correctly linked library. If the
//! facade module stopped carrying its C artifact, or the translated headers
//! stopped matching the C source, or the `libcurl` module stopped resolving by
//! name, this would stop building or stop producing the answers its program
//! checks -- and nothing inside the library would notice.
//!
//! `src/main.zig` is the API role's file. This file is only the graph that
//! builds it, and it deliberately repeats almost nothing: the library decides
//! which artifact is delivered, which platform macros it was compiled with and
//! which headers describe it, and this package learns all of that through the
//! dependency rather than by restating it.
//!
//! `zig build run` runs it. The parent package's `zig build consumer` runs or
//! installs this package as a nested build for the selected target, linkage and
//! dispatch mode -- it installs when this host cannot execute that target -- so
//! `zig build consumer -Dlinkage=dynamic` really does check the shared object
//! and not the default archive.

const std = @import("std");

/// The environment variable `src/main.zig` falls back to when the command line
/// names no provider.
///
/// Named here as well as in the program so the two cannot drift, and named in
/// this file's one place that has an opinion about it, below.
const provider_variable = "LIBCURL_TEST_PROVIDER";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The delivery and dispatch options are declared here rather than ignored,
    // so `zig build run -Dlinkage=dynamic` checks the shared object instead of
    // silently checking the default archive, and so the parent package's
    // `zig build consumer` can pass a configuration through to the dependency
    // instead of dropping it on the floor.
    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Which delivery of libcurl to check. Forwarded to the dependency; it " ++
            "decides the artifact, never anything in this package.",
    ) orelse .static;
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Check the dependency's runtime-loading dispatch instead of a linked " ++
            "one. Forwarded to the dependency. A program built this way has to " ++
            "name a provider with an explicit load() before any native call, " ++
            "which is src/main.zig's business and not this file's.",
    ) orelse false;

    const dep = b.dependency("libcurl", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
    });

    // There is deliberately no `-Dtls`, `-Dca-bundle` or `-Dca-path` option
    // here. Those belong to the library, which resolves the mbed-TLS dependency
    // itself and compiles the bundle paths in; a dependent that re-declared
    // them would be a second, disagreeing answer to a question the library has
    // already answered. A dependent that needs a different TLS package passes
    // the library's own option down through its own dependency call.

    // The system mode is deliberately *not* a `-D` option here, and that is not
    // an omission. The dependency resolves it through
    // `b.systemIntegrationOption`, which is fed by the build runner's
    // `-fsys=`/`-fno-sys=` flags and is never an entry in the `-D` map, so a
    // `b.option` declared here would have to be threaded down as a dependency
    // option to reach the same answer. It does not need to be: a dependency
    // shares its parent's `Graph` (`lib/std/Build.zig:352`) and
    // `system_library_options` is a field of it (`:116`, read at `:2731`), so
    // the flag the runner was given reaches the dependency's own
    // `systemIntegrationOption` call unchanged.
    //
    // That is what the parent package's `zig build consumer` forwards, as the
    // mode it resolved, and it is also why `zig build run -fsys=libcurl` in this
    // directory is the same check stated directly. Both spellings reach the one
    // switch; neither is a second code path.

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it -- libcurl is a C library and the socket,
    // resolver and mbed-TLS layers it links all come from the system libc; a
    // dependent states its own, and this program needs nothing beyond what the
    // library already brings. Adding it here would hide a library that forgot
    // to declare it.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("libcurl", dep.module("libcurl"));

    const exe = b.addExecutable(.{
        .name = "libcurl-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;

    // Forward `zig build run -- --provider <path>` to `src/main.zig`.
    run_exe.addPassthruArgs();

    // The provider variable is removed from the child's environment, so what
    // opened a shared object was the command line and not a value inherited
    // from the outer shell. Without this, a run that was supposed to prove the
    // command-line route silently proved the environment route whenever the
    // variable happened to be exported, and the recorded result would not say
    // which of the two had been exercised.
    //
    // `removeEnvironmentVariable` clones the graph's own map and drops one key
    // (`lib/std/Build/Step/Run.zig:584-603`), so everything the program still
    // needs -- the loader's search path, the dynamic linker's own variables --
    // is inherited as before. `clearEnvironment` would have removed those too
    // and broken `-Dlinkage=dynamic`.
    //
    // The environment route is still reachable: run the installed executable
    // yourself with the variable set. `zig build run` is the check, and the
    // check says one route.
    run_exe.removeEnvironmentVariable(provider_variable);

    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}