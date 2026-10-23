# SPDX-License-Identifier: curl

{ pkgs, ... }:

let
  # Use the pinned compiler version required by build.zig.zon.
  zig = pkgs.zig_0_17;

  libcurl = linkage: pkgs.callPackage ./package.nix { inherit linkage; };

  # Derive the writable checkout from this module, not the caller's directory.
  # Use a plain path string to avoid copying it into the read-only Nix store.
  sdk_root = builtins.toString ./.;

  # Put Zig caches outside the checkout, using configured cache or temporary paths.
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

  # Tasks require an external writable cache instead of writing into the checkout.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "libcurl devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # Enter this checkout and set caches first; tasks otherwise inherit the caller's working directory.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # Require ../mbed-tls from the manifest; no system backend or TLS-disabled fallback is used.
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

  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Give the separate consumer build its own cache directory.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  packages = [
    zig

    pkgs.pkg-config

    pkgs.coreutils

    pkgs.gnupg
  ];

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "The libcurl SDK requires Zig 0.17.0; nixpkgs resolved zig_0_17 to ${zig.version}";
    }
  ];

  # Apply cache isolation to interactive shell sessions too.
  enterShell = ''
    ${zig_caches}
  '';

  # Keep output derivations lazy; build a variant only when requested.
  outputs.static = libcurl "static";
  outputs.dynamic = libcurl "dynamic";
  outputs.default = libcurl "static";

  tasks = {
    # Install under a cache path outside the checkout, not Zig's default zig-out/.
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

    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        ${require_sibling_mbedtls}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

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

    # Enter the checkout root so cross-test discovers `cross-test.profile.sh`.
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

    # Keep the caller's project directory; nested devenv builds use its lock.
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