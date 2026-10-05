# Canonical development environment for the libcurl SDK.
#
# This is the environment a contributor should be in. It installs tools and
# nothing else: `packages` deliberately does not contain the SDK's own package,
# because entering a shell must not require building a library to have it.
#
# The package itself is defined once, in ./package.nix, and shared with
# flake.nix, so the two entry points cannot describe different builds. `outputs`
# below name that same derivation lazily -- they are attributes, not builds, so
# nothing is realised until `devenv build outputs.static` or
# `devenv build outputs.dynamic` is actually run.
#
# devenv.lock is not written here: the driver owns locks.
#
# Every tool below comes from the single nixpkgs revision pinned in
# devenv.yaml. None of them is fetched from a network at evaluation time: the
# input is a pinned source tree and each entry is an attribute of it. No tool
# version is asserted below except the Zig one, which is checked rather than
# claimed -- the assertion reads `zig.version` and fails the shell if nixpkgs
# ever resolves something else.
#
# Two facts about the environment a task actually runs in are handled once, in
# the `let` below, and every task uses them: devenv materialises a task as a
# generated shell program that inherits the caller's working directory, and
# `zig build` defaults both its local cache and its install prefix to
# directories inside the working tree. Neither is visible from a task body, and
# both decide whether a task can find this checkout or must write into it.
#
# SPDX-License-Identifier: curl

{ pkgs, ... }:

let
  # Kept as a value rather than inlined, so the version assertion below and the
  # package list cannot disagree about which compiler is meant. This is the
  # version `build.zig.zon` declares as `.minimum_zig_version` and the version
  # AGENTS.md §6 names as the compiler this workspace builds with. It is not the
  # only route to that compiler -- the driver's verification interface also names
  # a compiler in the host's approved cache -- and this shell does not paper over
  # a version mismatch by installing a bare `zig` shim.
  zig = pkgs.zig_0_16;

  libcurl = linkage: pkgs.callPackage ./package.nix { inherit linkage; };

  # The directory this module was evaluated against. `./.` is a path literal
  # resolved relative to the file that names it, so it is this checkout and
  # never the directory `devenv` was started from. `builtins.toString`
  # converts that path instead of interpolating it into a string, so what the
  # tasks below receive is this working tree: a plain `${./.}` would carry the
  # path's store context and copy this whole SDK into the read-only store, and
  # that copy is not the tree `build.zig` and `UPSTREAM.sha256` describe. No
  # host path is written in this file -- the value is read out of the module's
  # own location, so it tracks wherever this checkout is.
  sdk_root = builtins.toString ./.;

  # Where a task's build output goes. `zig build` keeps its local cache in
  # `.zig-cache/` and installs into `zig-out/`, both relative to the working
  # directory, and this checkout is a working tree on a volume mount that has to
  # stay byte-identical. A directory the caller exported always wins and is
  # never overwritten; otherwise it comes from `XDG_CACHE_HOME`, then `TMPDIR`,
  # and this file names no location of its own.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/libcurl/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/libcurl/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/libcurl/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/libcurl/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # The same rule with the one extra requirement a task has: it must be able to
  # name that directory. An environment with nowhere outside the checkout to
  # write stops here, with the reason, instead of filling the tree.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "libcurl devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # What every task below starts with. devenv materialises a task as a
  # generated shell program that inherits the caller's working directory, so
  # `devenv --from path:<sdk>` entered from a scratch project directory would
  # otherwise run each of these bodies where there is no `build.zig` and no
  # `UPSTREAM.sha256`. A per-task `cwd` would not reach that generated
  # program, and `$DEVENV_ROOT` is the scratch project itself -- exactly what
  # these bodies must not build in.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # The sibling this package cannot configure without, checked before the build
  # rather than after it. `build.zig.zon` declares exactly one dependency and it
  # is a relative path, `.{ .path = "../mbed-tls" }`, so `zig build` resolves it
  # against the directory holding this package. There is no vendored copy of
  # mbed-TLS, no bridge and no fallback, and there is deliberately no build
  # option that turns the TLS backend off -- so a missing sibling is a configure
  # failure, and the message should say which file is missing rather than leave
  # a reader to work it out from Zig's dependency error.
  #
  # PENDING-VERIFICATION: `../mbed-tls` has not landed yet. Until it does, every
  # task that calls `zig build` stops here, with this reason, and that is the
  # expected result -- not a defect in the task and not something to work around
  # with `-Dtls` or a system mbed-TLS.
  require_sibling_mbedtls = ''
    if [ ! -f "../mbed-tls/build.zig.zon" ]; then
      echo "libcurl devenv: ../mbed-tls/build.zig.zon is not present." >&2
      echo "build.zig.zon declares its only dependency as a relative path to the" >&2
      echo "mbed-TLS package, and this package has no vendored copy and no option" >&2
      echo "that turns TLS off, so it cannot configure without that sibling." >&2
      echo "Nothing here can supply it: the driver owns the sibling package." >&2
      exit 1
    fi
  '';

  # The flags every native build here shares: this workspace's eight jobs,
  # fixed, then the printed step list and a local cache outside the checkout.
  # `"''$@"` stays after them, so whatever a caller appended is still passed
  # on and still comes later; `devenv tasks run` forwards no argument of its
  # own, so it is the empty list on that route.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # The consumer package is a second build graph with its own manifest, so it
  # gets its own cache directory rather than sharing one with the library.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  packages = [
    zig

    # The delivery includes a pkg-config file, so the installed-closure gate is
    # a `pkg-config --exists libcurl` and a `pkg-config --libs` question. From
    # the same nixpkgs pin as the compiler; no version asserted, because none
    # was read.
    pkgs.pkg-config

    # `sha256sum -c UPSTREAM.sha256` is the integrity gate for the 418 vendored
    # upstream files, and it is the reason coreutils is named explicitly rather
    # than inherited from stdenv: the gate must not silently depend on whatever
    # the caller's environment happens to put on PATH.
    pkgs.coreutils

    # The release signature is one of the provenance facts recorded for this
    # import: the tarball's detached `.asc` and the release manager's public
    # key. Verifying it needs both files, and they live in the driver's import
    # scratch, not in this checkout, so there is deliberately no task below that
    # runs `gpg`: a task would fail for want of a file the package does not
    # ship, and that failure would say nothing about the package. The tool is
    # here for whoever re-checks that receipt by hand, with the files the
    # receipt names.
    pkgs.gnupg
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "The libcurl SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # The shell hook exports the same two directories the tasks use, by the same
  # rule, so an ordinary `devenv shell` session also leaves this checkout alone.
  # A value the caller exported is kept exactly as it is, and with nothing to
  # choose from the hook chooses nothing: only a task, which has to name the
  # directory, refuses to run.
  enterShell = ''
    ${zig_caches}
  '';

  # Lazy on purpose: naming a derivation realises nothing, and entering the
  # shell does not build either variant. `devenv build outputs.<name>` is the
  # real packaging route; the `sdk:package:*` tasks below are the route to the
  # Nix variants, and both need a lock the driver owns. The `cross-test` task
  # below is the route to the full 53-platform matrix.
  outputs.static = libcurl "static";
  outputs.dynamic = libcurl "dynamic";
  outputs.default = libcurl "static";

  # Every task name here is `namespace:name` and nothing else. devenv rejects a
  # name containing a character outside alphanumerics, `:`, `-` and `_` before
  # any shell runs -- a rejection recorded in a sibling SDK's shell after five
  # task names written with a `.` never loaded there -- so the names below use
  # a second `:` where a dot would have gone. The version of devenv that does
  # the rejecting was not read here, so none is claimed.
  tasks = {
    # Delivery output goes outside the checkout. The default step installs, and
    # `zig-out/` is a directory in the working tree, so the install prefix is
    # named here; the pkg-config file and the rpath the build normalises are
    # prefix-relative, so the installed tree is the same shape wherever it lands.
    "sdk:build" = {
      description = ''
        Compile the static library (the default linkage) and install the delivery
        tree under the external cache rather than in this checkout.
      '';
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${native_flags}
      '';
    };

    "sdk:build:dynamic" = {
      description = ''
        Compile the shared object instead of an archive, and install it under
        its own external prefix.
      '';
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
      '';
    };

    # These four run or compile; none of them installs, so each needs only the
    # external cache directory.
    "sdk:test" = {
      description = "Run the behavioural tests in Debug";
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build test ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build test -Doptimize=ReleaseSafe ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build smoke ${native_flags}
      '';
    };

    "sdk:check" = {
      description = ''
        Compile every public facade method and every example for each cross
        target this workspace publishes, without running any of them.
      '';
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        zig build check ${native_flags}
      '';
    };

    # The dependent package in `consumer/`, built and run as itself. It reaches
    # the library through the relative path dependency in its own manifest, so
    # this is the proof that `dep.module("libcurl")` resolves from outside this
    # package.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # The checker runs against this checkout's own bytes and file set, which is
    # what `UPSTREAM.sha256` describes, so it is entered here rather than in the
    # directory the task happened to start in. `sha256sum -c` runs first so a
    # mismatch is reported as a file and a digest rather than as a provenance
    # script's opinion about it. This is a source-integrity check, not a build
    # gate: it needs no sibling, no compiler and no cache, and it is the one
    # task here that can run before `mbed-tls/` lands.
    "sdk:provenance" = {
      description = ''
        Check the 418 recorded upstream digests, the exact native file set and the
        licence records. Source integrity, not a build gate.
      '';
      exec = ''
        ${in_sdk}
        sha256sum -c UPSTREAM.sha256
        bash tools/check-provenance.sh
      '';
    };

    # The published 53-platform matrix. `cross-test` is a host-local tool with
    # its own runner detection and its own scratch policy; it is not in nixpkgs
    # and inventing a nix attribute for it would put a different program under
    # its name. This task therefore looks for it, says where it looked, and
    # refuses when it is absent -- it never continues without it and never
    # substitutes a narrower command. Settings come from
    # `cross-test.profile.sh`, which the harness discovers by name from the
    # package root, so the task enters this checkout first: devenv runs a task
    # with the caller's working directory, which may be a scratch project with
    # no `build.zig` and no profile to discover.
    #
    # PENDING-VERIFICATION: a matrix run also needs the `../mbed-tls` sibling,
    # so this task is expected to fail at configure time on every cell until it
    # lands.
    "sdk:cross-test" = {
      description = ''
        Run the published 53-platform cross-test matrix over this package with
        the settings in cross-test.profile.sh.
      '';
      exec = ''
        cd "${sdk_root}" || exit 1
        if command -v cross-test >/dev/null 2>&1; then
          cross-test "$@"
        elif [ -x "$HOME/.local/bin/cross-test" ]; then
          "$HOME/.local/bin/cross-test" "$@"
        else
          echo "libcurl devenv: cross-test is not on PATH and" >&2
          echo "$HOME/.local/bin/cross-test is not executable. It is a host-local" >&2
          echo "harness, not a nix package, and this task will not stand in for it." >&2
          echo "The matrix it runs is documented in README.md; a profile is" >&2
          echo "settings, not the gate itself." >&2
          exit 1
        fi
      '';
    };

    # These two are the only bodies that do not enter this checkout, and that is
    # deliberate. They run a nested `devenv build`, which reads the project the
    # caller entered -- under `--from path:<sdk>` that is the scratch project
    # holding `.devenv/` and `devenv.lock` -- and its delivery output is a store
    # path, never a directory in this tree. Changing directory here would point
    # the nested command at a directory with no devenv state at all.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock
        is needed by this path; `devenv build outputs.static` resolves the
        pinned input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:dynamic" = {
      description = "Build the shared-object Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.dynamic";
    };
  };
}