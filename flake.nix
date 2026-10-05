# Flake interface for the libcurl SDK.
#
# Portable counterpart to devenv.nix. Both call ./package.nix, so the package a
# flake builds and the package devenv builds are the same derivation; this file
# only decides which systems are exposed and which variants of that derivation
# they get.
#
# Canonical development is `devenv shell` (see devenv.nix and .envrc). This
# flake exists so the SDK can be built and consumed off this host. `nix develop`
# here is parity, not the canonical entry point, and it deliberately does not
# build the SDK: entering a shell must not require building a library.
#
# flake.lock is not written here: the driver owns locks.
#
# SPDX-License-Identifier: curl

{
  description = "libcurl 8.22.0, the client-side transfer library, packaged for Zig 0.16";

  inputs = {
    # The same workspace-wide nixpkgs revision the sibling SDKs pin, so a flake
    # build of this package and a devenv shell for it resolve the same
    # `zig_0_16`. The two entry points still pin independently -- devenv.yaml
    # names its own input -- because they resolve in different contexts.
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # Unix systems only. This is the same boundary package.nix asserts: it
      # builds for the compiler's native target rather than hand-building a
      # cross triple, and it asserts buildPlatform.system == hostPlatform.system
      # rather than working around it. Documented in README.md, not papered over
      # here.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-freebsd"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          # `linkage` is Zig's own `std.builtin.LinkMode` spelling, passed
          # through to `-Dlinkage`. Two variants of one source, not two SDKs.
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_16;
          };
        in
        {
          # The default artifact. curl's own build systems produce a static
          # archive by default (`lib/Makefile.inc` has no shared-object default),
          # and the package's `-Dlinkage` default is `.static`.
          static = mk "static";

          # The same derivation with `-Dlinkage=dynamic`, delivering the shared
          # object instead. Named for the value passed, so the flag and the
          # output name cannot be read as two different things.
          dynamic = mk "dynamic";

          default = mk "static";
        });

      # No `libcurl-tls` output is exposed here, and there is no mbed-TLS input
      # to expose one from: the TLS backend is resolved by `zig build` through
      # the relative path dependency the manifest declares, out of the sibling
      # tree that package.nix ships as part of the source. A flake output for it
      # would be a second description of a package that lives in another
      # directory. PENDING-VERIFICATION: that sibling is not on disk yet, so
      # neither variant above can be realised until it lands.

      # Parity only. The canonical development environment is devenv.nix.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_16 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}